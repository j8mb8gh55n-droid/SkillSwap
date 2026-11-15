"""Run after test_reports_local.py in the same disposable container."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys

container = sys.argv[1]
network = subprocess.check_output(
    ["docker", "inspect", "--format", "{{.HostConfig.NetworkMode}} {{json .HostConfig.PortBindings}}", container],
    text=True,
).strip()
assert network == "none {}"
psql = ["docker", "exec", "-i", container, "psql", "-XqAt", "-U", "postgres",
        "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]

def sql(query, error=None):
    result = subprocess.run(psql, input=query, text=True, capture_output=True, timeout=15)
    if error:
        assert result.returncode and f"ERROR:  {error}:" in result.stderr
    else:
        assert result.returncode == 0, result.stderr
    return result.stdout.strip()

def actor(user, query, error=None):
    return sql(f"SET ROLE authenticated; SET request.jwt.claim.sub='{user}'; {query};", error)

reporter, reported, ordinary = [f"30000000-0000-0000-0000-00000000000{i}" for i in range(1, 4)]
moderator, second = [f"40000000-0000-0000-0000-00000000000{i}" for i in range(1, 3)]
drafts = Path("supabase/messaging/drafts")
sql("CREATE ROLE service_role;")
sql((drafts / "08b_chat_moderation.sql").read_text())
case = sql("SELECT id FROM chat_reports WHERE message_id IS NOT NULL ORDER BY created_at LIMIT 1;")
for user in (ordinary, reporter, reported):
    actor(user, "SELECT * FROM chat_moderation_queue()", "42501")
    actor(user, f"SELECT chat_moderation_detail('{case}')", "42501")
    actor(user, f"SELECT chat_moderation_action('{case}','resolved')", "42501")
actor(ordinary, f"INSERT INTO chat_moderation_private.members(user_id) VALUES ('{ordinary}')", "42501")
sql("SET ROLE anon; SELECT * FROM chat_moderation_queue();", "42501")
sql("SET ROLE service_role; SELECT * FROM chat_reports;", "42501")
sql(f"INSERT INTO chat_moderation_private.members(user_id) VALUES ('{moderator}'),('{second}'),('{reported}');")
assert actor(reported, "SELECT count(*) FROM chat_moderation_queue()") == "0"
actor(reported, f"SELECT chat_moderation_detail('{case}')", "55000")
actor(reported, f"SELECT chat_moderation_action('{case}','reviewed')", "55000")
actor(moderator, "SELECT * FROM chat_reports", "42501")
actor(moderator, "DELETE FROM chat_moderation_private.actions", "42501")
assert actor(moderator, "SELECT count(*) FROM chat_moderation_queue(p_limit => 1)") == "1"
assert actor(moderator, "SELECT count(*) FROM chat_moderation_queue() WHERE NOT has_evidence") == "1"
evidence = sql(f"SELECT message_id FROM chat_reports WHERE id='{case}';")
assert actor(moderator, f"SELECT chat_moderation_detail('{case}') #>> '{{evidence,id}}'") == evidence

def review(user):
    return subprocess.run(psql, input=f"SET ROLE authenticated; SET request.jwt.claim.sub='{user}'; "
                          f"SELECT chat_moderation_action('{case}','reviewed');",
                          text=True, capture_output=True, timeout=15)

with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(review, (moderator, second)))
assert sum(result.returncode == 0 for result in results) == 1
assert sum("ERROR:  55000:" in result.stderr for result in results) == 1
actor(second, f"SELECT chat_moderation_action('{case}','resolved')")
actor(second, f"SELECT chat_moderation_action('{case}','reviewed')", "55000")
winner = moderator if results[0].returncode == 0 else second
assert sql(f"""SELECT count(*) FROM chat_moderation_private.actions WHERE report_id='{case}'
    AND ((moderator_id='{winner}' AND previous_status='pending' AND new_status='reviewed')
      OR (moderator_id='{second}' AND previous_status='reviewed' AND new_status='resolved'))
    AND acted_at IS NOT NULL;""") == "2"
sql(f"UPDATE chat_moderation_private.members SET revoked_at=clock_timestamp() WHERE user_id='{moderator}';")
actor(moderator, f"SELECT chat_moderation_detail('{case}')", "42501")
thread = sql(f"SELECT conversation_id FROM chat_reports WHERE id='{case}';")
unused = sql(f"""SELECT m.id FROM chat_messages m WHERE m.conversation_id='{thread}'
    AND m.author_id='{reported}' AND NOT EXISTS (SELECT 1 FROM chat_reports r WHERE r.message_id=m.id) LIMIT 1;""")
actor(reporter, f"SELECT chat_report('{thread}','other',{unused})", "P0001")
assert sql("SELECT count(*) FROM chat_reports;") == "5"
sql((drafts / "08b_moderation_postflight_read_only.sql").read_text())
print("Moderator authorization, case evidence, concurrent review, audit attribution, revocation and report rate limit passed.")
