"""Run after the reconnection and reporting suites in the same disposable container."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys
import time

name = sys.argv[1]
assert subprocess.check_output(
    ["docker", "inspect", "--format", "{{.HostConfig.NetworkMode}} {{json .HostConfig.PortBindings}}", name],
    text=True,
).strip() == "none {}"
psql = ["docker", "exec", "-i", name, "psql", "-XqAt", "-U", "postgres", "-v", "ON_ERROR_STOP=1"]

def sql(query, error=None):
    result = subprocess.run(psql, input=query, capture_output=True, text=True, timeout=15)
    if error:
        assert result.returncode and error in result.stderr, result.stderr
    else:
        assert result.returncode == 0, result.stderr
    return result.stdout.strip()

def actor(user, query):
    return f"SET ROLE authenticated; SET request.jwt.claim.sub='{user}'; {query};"

def race(first, second):
    with subprocess.Popen(psql, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as owner:
        owner.stdin.write(f"BEGIN; {first} SELECT 'holding';\n")
        owner.stdin.flush()
        assert any(line.strip() == "holding" for line in owner.stdout)
        with ThreadPoolExecutor(max_workers=1) as pool:
            contender = pool.submit(sql, "SET application_name='skillswap06_waiter'; SET lock_timeout='8s'; " + second)
            try:
                for _ in range(60):
                    if sql("""SELECT count(*) FROM pg_stat_activity
                       WHERE application_name='skillswap06_waiter' AND cardinality(pg_blocking_pids(pid)) > 0;""") == "1":
                        break
                    time.sleep(.05)
                else:
                    raise AssertionError("Contender did not wait on the held lock")
            finally:
                owner.stdin.write("COMMIT;\n")
                owner.stdin.close()
            assert owner.wait(timeout=10) == 0, owner.stderr.read()
            contender.result()

a, b, c = (f"60000000-0000-0000-0000-00000000000{i}" for i in range(1, 4))
sql(f"INSERT INTO public.profiles(id) VALUES ('{a}'),('{b}'),('{c}');")
thread = sql(actor(a, f"SELECT chat_introduce('{b}','Synthetic initial message')"))
sql(actor(b, f"SELECT chat_respond('{thread}',true)"))
hide = actor(a, f"SELECT chat_hide('{thread}')")
send = actor(b, f"SELECT chat_send('{thread}','Synthetic reply')")
inbox = f"SELECT count(*) FROM chat_threads('inbox') t WHERE t->>'id'='{thread}'"
cursor = f"SELECT hidden_through_message_id FROM chat_conversation_preferences WHERE conversation_id='{thread}'"
latest = f"SELECT max(id) FROM public.chat_messages WHERE conversation_id='{thread}'"

race(send, hide)
assert sql(actor(a, cursor)) == sql(latest)
assert sql(actor(a, inbox)) == "0"
assert sql(actor(b, inbox)) == "1"
assert sql(actor(a, f"SELECT count(*) FROM chat_threads('thread',0,1,'{b}')")) == "1"
assert sql(actor(a, inbox)) == "0"
assert sql(actor(a, f"SELECT unread_count FROM chat_unread_counts() WHERE conversation_id='{thread}'")) == "1"

race(hide, send)
assert int(sql(actor(a, cursor))) < int(sql(latest))
assert sql(actor(a, inbox)) == "1"
assert sql(actor(a, f"SELECT unread_count FROM chat_unread_counts() WHERE conversation_id='{thread}'")) == "2"
for muted, expected in (("true", "t"), ("false", "f")):
    sql(actor(a, f"SELECT chat_set_muted('{thread}',{muted})"))
    assert sql(actor(a, f"SELECT muted FROM chat_visible_inbox WHERE id='{thread}'")) == expected
    assert sql(actor(b, f"SELECT muted FROM chat_visible_inbox WHERE id='{thread}'")) == "f"
assert sql(actor(c, "SELECT count(*) FROM chat_conversation_preferences")) == "0"
sql(actor(c, f"SELECT chat_hide('{thread}')"), "Conversation unavailable")
sql(actor(c, f"SELECT chat_set_muted('{thread}',true)"), "Conversation unavailable")
sql(actor(a, "UPDATE chat_conversation_preferences SET muted=true"), "permission denied")
sql(f"SET ROLE anon; SELECT chat_hide('{thread}');", "permission denied")
assert sql(f"SELECT count(*) FROM public.chat_messages WHERE conversation_id='{thread}';") == "3"
print("Both hide/send lock orders passed. Private mute, unread counts, profile reopening and retained history passed.")
