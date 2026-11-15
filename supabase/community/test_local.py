"""Test Migration 12 on a disposable PostgreSQL 17 instance with no network."""
import json
from pathlib import Path
import subprocess
import time
import uuid

folder = Path(__file__).resolve().parent
container = f"skillswap-community-{uuid.uuid4().hex[:12]}"

def docker(*args):
    return subprocess.run(["docker", *args], check=True, text=True, capture_output=True).stdout.strip()

def sql(query, error=None):
    proc = subprocess.run(
        ["docker", "exec", "-i", container, "psql", "-XqAt", "-U", "postgres",
         "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"],
        input=query, text=True, capture_output=True,
    )
    if error:
        assert proc.returncode and f"ERROR:  {error}:" in proc.stderr, proc.stderr
    else:
        assert not proc.returncode, proc.stderr
    return proc.stdout.strip()

def actor(user, query):
    return sql(f"SET ROLE authenticated; SET request.jwt.claim.sub='{user}'; {query}")

a, b, c = [f"00000000-0000-0000-0000-00000000000{i}" for i in range(1, 4)]

docker("run", "--rm", "-d", "--pull=never", "--network", "none", "--name", container,
       "-e", "POSTGRES_HOST_AUTH_METHOD=trust", "postgres:17")
try:
    assert docker("inspect", "--format", "{{.HostConfig.NetworkMode}} {{json .HostConfig.PortBindings}}", container) == "none {}"
    for _ in range(40):
        try:
            docker("exec", container, "pg_isready", "-U", "postgres", "-h", "127.0.0.1")
            break
        except subprocess.CalledProcessError:
            time.sleep(.25)
    else:
        raise RuntimeError("PostgreSQL startup timeout")

    sql(f"""
      CREATE ROLE anon;
      CREATE ROLE authenticated;
      CREATE SCHEMA auth;
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
        SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
      $$;
      GRANT USAGE ON SCHEMA auth TO authenticated;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated;
      CREATE TABLE profiles(id uuid PRIMARY KEY, full_name text, discoverable_in_explore boolean DEFAULT true);
      CREATE TABLE skills(id bigint PRIMARY KEY, name text);
      ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
      ALTER TABLE skills ENABLE ROW LEVEL SECURITY;
      CREATE POLICY profiles_select ON profiles FOR SELECT TO authenticated USING (true);
      CREATE POLICY profiles_update ON profiles FOR UPDATE TO authenticated USING (auth.uid()=id) WITH CHECK (auth.uid()=id);
      CREATE POLICY skills_select ON skills FOR SELECT TO authenticated USING (true);
      INSERT INTO profiles VALUES ('{a}','A',true),('{b}','B',true),('{c}','C',true);
      INSERT INTO skills VALUES (2,'Python'),(5,'UI/UX');
    """)
    before = json.loads(sql((folder / "preflight_read_only.sql").read_text()))
    assert not before["type_conflicts"]
    sql((folder / "12_community_posts.sql").read_text())
    report = json.loads(sql((folder / "postflight_read_only.sql").read_text()))
    after = json.loads(sql((folder / "preflight_read_only.sql").read_text()))
    assert len(report["tables"]) == 3 and all(t["relrowsecurity"] for t in report["tables"])
    assert len(report["policies"]) == 6 and all(i["valid"] for i in report["indexes"])
    assert report["bookmark_columns"] == {"post_id": True, "student_id": False}
    assert report["rpc"]["prosecdef"] and report["rpc"]["proconfig"] == ['search_path=""']
    assert report["rpc"]["authenticated_execute"] and not report["rpc"]["anon_execute"] and not report["rpc"]["public_execute"]
    for section, key in (("relations", "relname"), ("columns", "relation"), ("policies", "tablename"),
                         ("constraints", "table"), ("functions", "signature")):
        assert (before[section] or []) == [
            x for x in after[section] if not x[key].startswith("community_")
        ], section
    for table in ("community_posts", "community_post_skills", "community_saved_posts"):
        sql(f"SET ROLE anon; SELECT * FROM {table};", "42501")
    sql("SET ROLE anon; SELECT community_save_post('question','Title','Body',ARRAY[2]::bigint[]);", "42501")
    sql("SET ROLE authenticated; SELECT community_save_post('question','Title','Body',ARRAY[2]::bigint[]);", "42501")
    assert sql("SET ROLE authenticated; SELECT count(*) FROM community_posts;") == "0"

    def save(kind="question", title="'Title'", body="'Body'", tags="ARRAY[2]::bigint[]", link="NULL", post=None):
        return f"SELECT community_save_post('{kind}',{title},{body},{tags},{link},{'NULL' if not post else repr(post)});"

    post = actor(a, save(link="'https://example.com/notes?q=skill#topic'"))
    assert actor(b, f"SELECT author_id FROM community_posts WHERE id='{post}';") == a
    actor(a, f"UPDATE profiles SET discoverable_in_explore=false WHERE id='{a}';")
    assert actor(b, f"SELECT count(*) FROM community_posts p JOIN profiles pr ON pr.id=p.author_id WHERE p.id='{post}';") == "1"

    def expect_error(user, query, state):
        sql(f"SET ROLE authenticated; SET request.jwt.claim.sub='{user}'; {query}", state)

    expect_error(b, save(post=post), "42501")
    assert actor(b, f"DELETE FROM community_posts WHERE id='{post}' RETURNING id;") == ""
    expect_error(a, f"UPDATE community_posts SET author_id='{b}' WHERE id='{post}';", "42501")
    expect_error(a, f"DELETE FROM community_post_skills WHERE post_id='{post}';", "42501")
    expect_error(a, f"INSERT INTO community_posts(author_id,kind,title,body) VALUES ('{a}','tip','X','Y');", "42501")
    for tags, state in (("NULL", "22023"), ("ARRAY[]::bigint[]", "22023"),
                        ("ARRAY[2,2]::bigint[]", "22023"), ("ARRAY[NULL]::bigint[]", "22023"),
                        ("ARRAY[999]::bigint[]", "23503"), ("ARRAY(SELECT generate_series(1,11)::bigint)", "22023")):
        expect_error(a, save(title="'Changed'", tags=tags, post=post), state)
    for unsafe in ("http://example.com/x", "https://a@example.com/", "https://",
                   "https://bad-.example.com", "https://example.com/a b", r"https://example.com/a\b"):
        expect_error(a, save(link=repr(unsafe) if "\\" not in unsafe else "'" + unsafe + "'"), "23514")
    expect_error(a, save(title="repeat('x',121)"), "23514")
    expect_error(a, save(body="repeat('x',4001)"), "23514")
    expect_error(a, save(title="chr(9)||chr(10)"), "23514")
    expect_error(a, save(kind="story"), "23514")
    expect_error(a, save(tags="ARRAY[2,999]::bigint[]"), "23503")
    assert actor(b, f"SELECT title FROM community_posts WHERE id='{post}';") == "Title"
    assert actor(b, f"SELECT skill_id FROM community_post_skills WHERE post_id='{post}';") == "2"
    assert actor(b, "SELECT count(*) FROM community_posts;") == "1"

    assert actor(a, save(kind="resource", title="'Edited'", tags="ARRAY[5,2]::bigint[]", post=post)) == post
    assert actor(b, f"SELECT kind||':'||title||':'||(updated_at>=created_at) FROM community_posts WHERE id='{post}';") == "resource:Edited:true"
    assert actor(b, f"SELECT string_agg(skill_id::text,',' ORDER BY skill_id) FROM community_post_skills WHERE post_id='{post}';") == "2,5"

    def bookmark(user, target):
        actor(user, f"INSERT INTO community_saved_posts(post_id) VALUES ('{target}') ON CONFLICT(student_id,post_id) DO NOTHING;")

    bookmark(b, post)
    bookmark(b, post)
    bookmark(c, post)
    assert actor(b, "SELECT count(*) FROM community_saved_posts;") == "1"
    assert actor(a, "SELECT count(*) FROM community_saved_posts;") == "0"
    expect_error(a, f"INSERT INTO community_saved_posts(student_id, post_id) VALUES ('{b}','{post}');", "42501")
    assert actor(a, f"DELETE FROM community_saved_posts WHERE post_id='{post}' RETURNING post_id;") == ""
    actor(b, f"DELETE FROM community_saved_posts WHERE post_id='{post}';")
    assert actor(b, "SELECT count(*) FROM community_saved_posts;") == "0"
    assert actor(c, "SELECT count(*) FROM community_saved_posts;") == "1"
    bookmark(b, post)
    actor(a, f"DELETE FROM community_posts WHERE id='{post}';")
    assert sql("SELECT count(*) FROM community_post_skills; SELECT count(*) FROM community_saved_posts;") == "0\n0"

    other = actor(a, save(kind="project"))
    bookmark(b, other)
    sql(f"DELETE FROM profiles WHERE id='{b}';")
    assert sql("SELECT count(*) FROM community_posts; SELECT count(*) FROM community_saved_posts;") == "1\n0"
    sql(f"DELETE FROM profiles WHERE id='{a}';")
    assert sql("SELECT count(*) FROM community_posts; SELECT count(*) FROM community_post_skills;") == "0\n0"
    print("PASS: anonymous denial, author ownership, strict validation, atomic tags, opt-out-independent reads, private idempotent bookmarks, post/profile cleanup, and metadata checks.")
finally:
    docker("rm", "-f", container)
