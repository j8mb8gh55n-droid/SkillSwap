"""Run after the Migration 05 and reconnection suites in a disposable container."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys

container = sys.argv[1]
docker = ["docker"]
network = subprocess.check_output(
    docker + ["inspect", "--format", "{{.HostConfig.NetworkMode}} {{json .HostConfig.PortBindings}}", container],
    text=True,
).strip()
assert network == "none {}"
psql = docker + ["exec", "-i", container, "psql", "-XqAt", "-U", "postgres",
                 "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]

def sql(query, expected_error=None):
    result = subprocess.run(psql, input=query, text=True, capture_output=True, timeout=15)
    if expected_error:
        assert result.returncode and f"ERROR:  {expected_error}:" in result.stderr, expected_error
    else:
        assert not result.returncode, result.stderr
    return result.stdout.strip()

def actor(student, query, error=None):
    return sql(f"SET ROLE authenticated; SET request.jwt.claim.sub='{student}'; {query};", error)

a, b, c = [f"30000000-0000-0000-0000-00000000000{i}" for i in range(1, 4)]
sql(Path("supabase/messaging/drafts/08_chat_reports.sql").read_text())
sql(f"INSERT INTO public.profiles(id) VALUES ('{a}'), ('{b}'), ('{c}');")
thread = actor(a, f"SELECT chat_introduce('{b}','Synthetic introduction')")
actor(b, f"SELECT chat_respond('{thread}',true)")
peer_messages = [actor(b, f"SELECT chat_send('{thread}','Synthetic evidence')") for _ in range(6)]
own = actor(a, f"SELECT chat_send('{thread}','Synthetic message')")
other = actor(b, f"SELECT chat_introduce('{c}','Synthetic other thread')")
foreign = sql(f"SELECT id FROM chat_messages WHERE conversation_id='{other}'")
report = f"SELECT chat_report('{thread}','harassment')"
actor(c, report, "55000")
sql(f"SET ROLE anon; {report};", "42501")
actor(a, f"SELECT chat_report('{thread}','other',{own})", "55000")
actor(a, f"SELECT chat_report('{thread}','other',{foreign})", "55000")
actor(a, f"SELECT chat_report('{thread}','invalid')", "23514")
actor(a, f"SELECT chat_report('{thread}','other',NULL,repeat('x',501))", "23514")
for student in (a, b, c):
    actor(student, "SELECT count(*) FROM chat_reports", "42501")
actor(c, f"""INSERT INTO chat_reports (reporter_id,conversation_id,reported_id,reason)
    VALUES ('{a}','{thread}','{b}','other')""", "42501")
actor(a, report)
actor(a, report, "23505")
actor(b, f"SELECT chat_block('{a}')")
with ThreadPoolExecutor() as pool:
    results = list(pool.map(lambda message: subprocess.run(
        psql, input=f"SET ROLE authenticated; SET request.jwt.claim.sub='{a}'; "
                    f"SELECT chat_report('{thread}','other',{message});",
        text=True, capture_output=True, timeout=15
    ), peer_messages))
assert sum(result.returncode == 0 for result in results) == 4
assert sum("ERROR:  P0001:" in result.stderr for result in results) == 2
assert sql(f"SELECT count(*) FROM chat_reports WHERE reporter_id='{a}' AND reported_id='{b}'") == "5"
assert sql(f"SELECT status FROM chat_conversations WHERE id='{thread}'") == "blocked"
print("Report privacy, evidence validation, duplicate rejection, concurrent rate limit and blocked-thread reporting passed.")
