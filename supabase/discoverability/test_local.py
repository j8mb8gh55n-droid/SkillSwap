"""Run with a disposable PostgreSQL 17 Docker container. No network or mounted files."""
import json
from pathlib import Path
import subprocess
import time
import uuid

directory = Path(__file__).resolve().parent
messaging = directory.parent / "messaging"
container = f"skillswap-discoverability-{uuid.uuid4().hex[:12]}"

def docker(*args, **kwargs):
    return subprocess.run(["docker", *args], check=True, text=True, capture_output=True, **kwargs).stdout.strip()

def sql(query, expected_error=None):
    proc = subprocess.run(
        ["docker", "exec", "-i", container, "psql", "-XqAt", "-U", "postgres",
         "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"],
        input=query, text=True, capture_output=True,
    )
    if expected_error:
        assert proc.returncode and f"ERROR:  {expected_error}:" in proc.stderr, proc.stderr
    else:
        assert not proc.returncode, proc.stderr
    return proc.stdout.strip()

def run_file(path):
    return sql(path.read_text())

a, b, c, d, e = [f"00000000-0000-0000-0000-00000000000{i}" for i in range(1, 6)]

def actor(user, query):
    return f"SET ROLE authenticated; SET request.jwt.claim.sub='{user}'; {query}"

def spot(page_after="NULL", limit=100):
    return json.loads(sql(actor(b, f"""
        SELECT coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.id), '[]'::jsonb)
        FROM public.discover_students({page_after}, {limit}) p;
    """)))

docker("run", "--rm", "-d", "--pull=never", "--network", "none", "--name", container,
       "-e", "POSTGRES_HOST_AUTH_METHOD=trust", "postgres:17")
try:
    assert docker("inspect", "--format", "{{.HostConfig.NetworkMode}} {{json .HostConfig.PortBindings}}",
                  container) == "none {}"
    for _ in range(40):
        try:
            docker("exec", container, "pg_isready", "-U", "postgres", "-h", "127.0.0.1")
            break
        except subprocess.CalledProcessError:
            time.sleep(0.25)
    else:
        raise RuntimeError("PostgreSQL startup timeout")

    sql(f"""
        CREATE ROLE anon;
        CREATE ROLE authenticated;
        CREATE SCHEMA auth;
        CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
          SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
        GRANT USAGE ON SCHEMA auth TO authenticated;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
        CREATE TABLE profiles(id uuid PRIMARY KEY, full_name text NOT NULL, major text,
                              bio text, avatar_url text, availability_status text);
        CREATE TABLE skills(id bigint PRIMARY KEY, name text NOT NULL, category text NOT NULL);
        CREATE TABLE student_skills(id bigint PRIMARY KEY, student_id uuid REFERENCES profiles(id),
            skill_id bigint REFERENCES skills(id), skill_type text NOT NULL, experience_level text,
            UNIQUE(student_id, skill_id, skill_type));
        CREATE TABLE exchanges(id integer PRIMARY KEY, requester_id uuid REFERENCES profiles(id),
                               recipient_id uuid REFERENCES profiles(id), status text);
        CREATE TABLE sessions(id integer PRIMARY KEY, exchange_id integer REFERENCES exchanges(id), status text);
        ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
        ALTER TABLE skills ENABLE ROW LEVEL SECURITY;
        ALTER TABLE student_skills ENABLE ROW LEVEL SECURITY;
        ALTER TABLE exchanges ENABLE ROW LEVEL SECURITY;
        ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
        CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (true);
        CREATE POLICY profiles_update ON profiles FOR UPDATE TO authenticated
            USING ((SELECT auth.uid()) = id) WITH CHECK ((SELECT auth.uid()) = id);
        CREATE POLICY skills_select ON skills FOR SELECT TO authenticated USING (true);
        CREATE POLICY student_skills_select ON student_skills FOR SELECT TO authenticated USING (true);
        CREATE POLICY exchanges_select ON exchanges FOR SELECT TO authenticated
            USING (auth.uid() IN (requester_id, recipient_id));
        CREATE POLICY sessions_select ON sessions FOR SELECT TO authenticated
            USING (EXISTS (SELECT 1 FROM exchanges e WHERE e.id = sessions.exchange_id));
        INSERT INTO profiles(id, full_name) VALUES ('{a}','A'),('{b}','B'),('{c}','C'),('{d}','D');
        INSERT INTO skills VALUES (2,'Python','Technology'),(5,'UI/UX Design','Design');
        INSERT INTO student_skills VALUES
          (1,'{a}',2,'teach','experienced'),(2,'{a}',5,'learn',NULL),
          (3,'{b}',5,'teach',NULL),(4,'{b}',2,'learn',NULL),(5,'{c}',2,'teach',NULL);
        INSERT INTO exchanges VALUES (1,'{a}','{b}','accepted');
        INSERT INTO sessions VALUES (1,1,'confirmed');
    """)
    run_file(messaging / "05_direct_messaging.sql")
    for name in ("07_chat_block_ownership", "10_chat_reconnection", "08_chat_reports", "06_conversation_preferences"):
        run_file(messaging / "drafts" / f"{name}.sql")
    thread = sql(actor(a, f"SELECT chat_introduce('{b}', 'Local test');"))
    sql(actor(b, f"SELECT chat_respond('{thread}', true);"))
    before = json.loads(run_file(directory / "preflight_read_only.sql"))

    run_file(directory / "11_discoverable_in_explore.sql")
    sql(f"INSERT INTO profiles(id, full_name) VALUES ('{e}','E');")
    assert sql("SELECT count(*) FROM profiles WHERE discoverable_in_explore;") == "5"
    report = json.loads(run_file(directory / "postflight_read_only.sql"))
    after = json.loads(run_file(directory / "preflight_read_only.sql"))
    assert report["column"] == {"attnotnull": True, "type": "boolean", "default_expression": "true"}
    assert report["profile_rls"] and report["rpc"]["security_invoker"]
    assert report["rpc"]["authenticated_execute"] and not report["rpc"]["anon_execute"]
    assert not report["rpc"]["public_execute"] and report["rpc"]["proconfig"] == ['search_path=""']
    for key in ("policies", "triggers", "constraints", "indexes", "relations", "roles", "effective_table_privileges"):
        assert before[key] == after[key], key
    assert before["functions"] == [f for f in after["functions"] if not f["signature"].startswith("discover_students(")]

    assert sql("SET ROLE anon; SELECT count(*) FROM profiles;") == "0"
    assert sql("SET ROLE anon; SELECT count(*) FROM student_skills;") == "0"
    sql("SET ROLE anon; SELECT * FROM discover_students();", "42501")
    assert sql("SET ROLE authenticated; SELECT count(*) FROM discover_students();") == "0"
    assert sql(actor(b, f"UPDATE profiles SET discoverable_in_explore=false WHERE id='{a}' RETURNING id;")) == ""
    first = spot(limit=1)
    assert [p["id"] for p in first] == [a]
    assert [(s["skill_type"], s["skills"]["id"]) for s in first[0]["skill_links"]] == [("teach", 2), ("learn", 5)]

    sql(actor(c, f"UPDATE profiles SET discoverable_in_explore=false WHERE id='{c}';"))
    assert [p["id"] for p in spot(f"'{a}'", 1)] == [d]
    sql(actor(a, f"UPDATE profiles SET discoverable_in_explore=false WHERE id='{a}';"))
    assert [p["id"] for p in spot(limit=2)] == [d, e]
    assert all(not p["skill_links"] for p in spot())

    # Exact-ID read used for saved profiles and authorized chat/exchange profile entry points.
    assert sql(actor(b, f"SELECT full_name FROM profiles WHERE id='{a}';")) == "A"
    assert sql(actor(b, f"SELECT count(*) FROM profiles p JOIN student_skills s ON p.id=s.student_id WHERE p.id='{a}';")) == "2"
    for viewer, other in [(b, a), (a, b)]:
        assert sql(actor(viewer, f"SELECT count(*) FROM chat_threads('thread',0,20,'{other}');")) == "1"
        assert sql(actor(viewer, f"SELECT count(*) FROM chat_messages WHERE conversation_id='{thread}';")) == "1"
        assert sql(actor(viewer, "SELECT count(*) FROM exchanges e JOIN profiles p ON p.id=e.requester_id;")) == "1"
        assert sql(actor(viewer, "SELECT count(*) FROM sessions WHERE status='confirmed';")) == "1"
    assert sql(actor(d, "SELECT count(*) FROM chat_threads('inbox');")) == "0"
    assert sql(actor(d, "SELECT count(*) FROM exchanges; SELECT count(*) FROM sessions;")) == "0\n0"

    sql(actor(a, f"UPDATE profiles SET discoverable_in_explore=true WHERE id='{a}';"))
    assert [p["id"] for p in spot(f"'{d}'")] == [e]
    assert [p["id"] for p in spot()] == [a, d, e]
    print("PASS: defaults, ownership, anonymous denial, visibility toggles, cursor changes, attached skills, exact-ID reads, Messaging 05/06/07/08/10, exchange/session policy fixtures, and unchanged metadata.")
finally:
    docker("rm", "-f", container)
