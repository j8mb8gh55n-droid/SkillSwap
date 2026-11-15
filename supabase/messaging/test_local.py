"""Run against a disposable PostgreSQL container with networking disabled."""
import argparse
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("container")
args = parser.parse_args()
docker = ["docker"]
base = docker + ["exec", "-i", args.container, "psql", "-XqAt", "-U", "postgres",
                 "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]
network = subprocess.check_output(
    docker + ["inspect", "--format", "{{.HostConfig.NetworkMode}} {{json .HostConfig.PortBindings}}",
              args.container], text=True
).strip()
assert network == "none {}", "Use a container without networking or published ports"

a, b, c, d, e = [f"00000000-0000-0000-0000-00000000000{i}" for i in range(1, 6)]


def sql(query, error=None):
    result = subprocess.run(base, input=query, capture_output=True, text=True)
    if error:
        assert result.returncode and f"ERROR:  {error}:" in result.stderr, result.stderr
    else:
        assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def actor(user, statement):
    return f"SET ROLE authenticated; SET request.jwt.claim.sub='{user}'; {statement};"


def introduce(sender, receiver, body="Hello"):
    return actor(sender, f"SELECT chat_introduce('{receiver}','{body}')")


def send(sender, thread, body="Hi"):
    return actor(sender, f"SELECT chat_send('{thread}','{body}')")


def respond(recipient, thread, accept):
    return actor(recipient, f"SELECT chat_respond('{thread}',{accept})")


def verify():
    directory = Path(__file__).resolve().parent
    sql(f"""
      CREATE ROLE anon;
      CREATE ROLE authenticated;
      CREATE SCHEMA auth;
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      $$ SELECT nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
      GRANT USAGE ON SCHEMA auth TO authenticated;
      CREATE TABLE public.profiles (id uuid PRIMARY KEY);
      INSERT INTO public.profiles VALUES ('{a}'),('{b}'),('{c}'),('{d}'),('{e}');
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
    """)
    sql((directory / "preflight_read_only.sql").read_text())
    sql((directory / "05_direct_messaging.sql").read_text())
    thread = sql(introduce(a, b))
    assert sql(actor(b, f"SELECT count(*) FROM chat_messages WHERE conversation_id='{thread}'")) == "1"
    assert sql(actor(c, "SELECT count(*) FROM chat_messages")) == "0"
    assert sql(actor(c, "SELECT count(id) FROM chat_conversations")) == "0"
    sql(introduce(a, b), "55000")
    sql(introduce(b, a), "55000")
    sql(send(a, thread), "55000")
    sql(send(b, thread), "55000")
    sql(send(c, thread), "55000")
    sql(respond(a, thread, "true"), "55000")
    sql(respond(c, thread, "true"), "55000")
    sql(respond(b, thread, "true"))
    sql(send(c, thread), "55000")
    assert sql(introduce(b, a)) == thread
    first = sql(send(a, thread))
    second = sql(send(b, thread))
    assert sql(actor(a, "SELECT unread_count FROM chat_unread_counts()")) == "1"
    sql(actor(a, f"SELECT chat_mark_read('{thread}',{second})"))
    sql(actor(a, f"SELECT chat_mark_read('{thread}',{first})"))
    assert sql(actor(a, "SELECT unread_count FROM chat_unread_counts()")) == "0"
    sql(actor(b, "SELECT initiator_read_through FROM chat_conversations"), "42501")
    sql(actor(b, f"INSERT INTO chat_messages(conversation_id,author_id,body) VALUES ('{thread}','{a}','Forged')"), "42501")
    sql(actor(b, f"UPDATE chat_conversations SET initiator_id='{c}' WHERE id='{thread}'"), "42501")
    sql(actor(b, f"UPDATE chat_messages SET author_id='{a}' WHERE id={second}"), "42501")
    sql(send(a, thread, " " * 4), "23514")
    sql(send(a, thread, "x" * 2001), "23514")
    sql(introduce(a, a), "22023")
    sql(introduce(a, "00000000-0000-0000-0000-000000000099"), "23503")
    sql(introduce(a, c, " "), "23514")
    declined = sql(introduce(a, c))
    sql(respond(c, declined, "false"))
    sql(respond(c, declined, "true"), "55000")
    sql(introduce(c, a), "55000")
    sql(introduce(a, c), "55000")
    sql(send(c, declined), "55000")
    sql(actor(b, f"SELECT chat_block('{a}')"))
    sql(send(a, thread), "55000")
    sql(send(b, thread), "55000")
    sql(actor(d, f"SELECT chat_block('{a}')"))
    sql(introduce(a, d), "55000")
    sql(introduce(d, a), "55000")
    sql(f"SET ROLE anon; SELECT chat_send('{thread}','Hi');", "42501")

    with subprocess.Popen(base, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True) as left:
        left.stdin.write("BEGIN; " + introduce(d, e) + " SELECT 'held';\n")
        left.stdin.flush()
        assert left.stdout.readline().strip()
        assert left.stdout.readline().strip() == "held"
        with subprocess.Popen(base, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True) as right:
            right.stdin.write(introduce(e, d) + "\n")
            right.stdin.close()
            right.stdin = None
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if sql("SELECT count(*) FROM pg_stat_activity WHERE wait_event_type='Lock' "
                           "AND query LIKE 'SELECT chat_introduce(%';") == "1":
                        break
                    time.sleep(0.05)
                else:
                    raise AssertionError("The concurrent introduction never waited on the pair index")
            finally:
                left.stdin.write("COMMIT;\n")
                left.stdin.flush()
                left.stdin.close()
                left.stdin = None
                assert left.wait(timeout=5) == 0
            _, errors = right.communicate(timeout=5)
            assert right.returncode and "ERROR:  55000:" in errors, errors
    assert sql(actor(d, f"SELECT count(id) FROM chat_conversations WHERE recipient_id='{e}'")) == "1"
    assert sql(actor(e, "SELECT count(*) FROM chat_messages")) == "1"
    assert sql((directory / "verify_read_only.sql").read_text()).splitlines()[-1] == "0|0"
    print("Passed messaging transitions, RLS, forgery checks, unread state, invalid input, rollback on failed introduction, and concurrent reverse introductions.")


if __name__ == "__main__":
    verify()
