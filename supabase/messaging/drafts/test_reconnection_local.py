from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess, sys, time

# Run Migration 05's test suite in this disposable container first.
network = subprocess.check_output(
    ['docker', 'inspect', '--format', '{{.HostConfig.NetworkMode}} {{json .HostConfig.PortBindings}}', sys.argv[1]],
    text=True,
).strip()
assert network == 'none {}', 'Use a container without networking or published ports'

base = ['docker','exec','-i',sys.argv[1],'psql','-XqAt','-U','postgres','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']
def run(q, error=None):
    r = subprocess.run(base,input=q,text=True,capture_output=True,timeout=15)
    if error:
        assert r.returncode and f'ERROR:  {error}:' in r.stderr, r.stderr
    else:
        assert not r.returncode, r.stderr
    return r.stdout.strip()
def actor(u, q):
    return f"SET ROLE authenticated; SET request.jwt.claim.sub='{u}'; {q};"
a,b,c,d = [f"20000000-0000-0000-0000-00000000000{i}" for i in range(1,5)]
run('INSERT INTO public.profiles VALUES '+','.join(f"('{u}')" for u in (a,b,c,d))+';')
run(actor(c, f"SELECT chat_block('{d}')"))
run(Path('supabase/messaging/drafts/07_chat_block_ownership.sql').read_text())
run(actor(c, f"SELECT chat_block('{d}'); SELECT chat_unblock('{d}')"))
assert run(actor(c, f"SELECT status FROM chat_conversations WHERE recipient_id='{d}'")) == 'blocked'
thread = run(actor(a, f"SELECT chat_introduce('{b}','hello')"))
run(actor(b, f"SELECT chat_respond('{thread}',true)"))
def block(who, other):
    return actor(who, f"SELECT chat_block('{other}')")
def unblock(who, other):
    return actor(who, f"SELECT chat_unblock('{other}')")
def status():
    return run(actor(a, f"SELECT status FROM chat_conversations WHERE id='{thread}'"))
def race(first, second, error=None):
    with subprocess.Popen(base, stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) as holder:
        holder.stdin.write("BEGIN; "+first+" SELECT 'holding';\n")
        holder.stdin.flush()
        assert next((line.strip() for line in holder.stdout if line.strip() == 'holding'), '') == 'holding'
        with ThreadPoolExecutor() as pool:
            waiting = pool.submit(run, "SET application_name='skillswap07_contender'; SET lock_timeout='8s'; "+second, error)
            try:
                for _ in range(70):
                    if run("SELECT count(*) FROM pg_stat_activity WHERE application_name='skillswap07_contender' AND cardinality(pg_blocking_pids(pid)) > 0;") == '1':
                        break
                    time.sleep(.05)
                else:
                    raise AssertionError('Contender did not wait on holder')
            finally:
                holder.stdin.write('COMMIT;\n')
                holder.stdin.close()
            assert holder.wait(timeout=10) == 0, holder.stderr.read()
            waiting.result()
run('ALTER TABLE public.profiles ADD COLUMN full_name text, ADD COLUMN avatar_url text;')
run(Path('supabase/messaging/drafts/10_chat_reconnection.sql').read_text())
def reconnect(who, conv=thread, text='Reconnect'):
    return actor(who,f"SELECT chat_reconnect('{conv}','{text}')")
def send(who, conv=thread):
    return actor(who,f"SELECT chat_send('{conv}','follow-up')")
def respond(who, accept, conv=thread):
    mid=run(f"SELECT message_id FROM public.chat_reconnections WHERE conversation_id='{conv}'")
    return actor(who,f"SELECT chat_respond_to_reconnection('{conv}',{mid},{str(accept).lower()})")
run(block(a,b))
run(block(b,a))
run(unblock(a,b))
run(reconnect(a),'55000')
run(reconnect(b),'55000')
race(unblock(b,a),reconnect(b))
assert status() == 'pending'
assert run(actor(a,f"SELECT count(*) FROM chat_threads('received') t WHERE t->>'id'='{thread}'")) == '1'
assert run(actor(b,f"SELECT count(*) FROM chat_threads('sent') t WHERE t->>'id'='{thread}'")) == '1'
assert run(actor(c,f"SELECT count(*) FROM chat_threads('thread',0,1,'{b}') t WHERE t->>'id'='{thread}'")) == '0'
run(actor(b,f"SELECT chat_respond('{thread}',true)"),'55000')
run(actor(a,f"SELECT chat_respond_to_reconnection('{thread}',0,true)"),'55000')
run(reconnect(a),'55000')
run(reconnect(b),'55000')
run(send(a),'55000')
run(send(b),'55000')
run(respond(b,True),'55000')
run(respond(a,True))
run(send(a))
run(send(b))
run(block(a,b))
run(unblock(a,b))
run(reconnect(a),'55000')
assert status()=='declined'
assert run(actor(a,f"SELECT count(*) FROM chat_threads('inbox') t WHERE t->>'id'='{thread}'")) == '1'
run(Path("supabase/messaging/drafts/06_conversation_preferences.sql").read_text())
run(f"INSERT INTO public.chat_conversation_preferences (conversation_id,student_id,hidden_through_message_id) SELECT '{thread}','{a}',max(id) FROM chat_messages WHERE conversation_id='{thread}'")
assert run(actor(a,f"SELECT count(*) FROM chat_threads('inbox') t WHERE t->>'id'='{thread}'")) == '0'
assert run(actor(b,f"SELECT count(*) FROM chat_threads('inbox') t WHERE t->>'id'='{thread}'")) == '1'
assert run(actor(a,f"SELECT count(*) FROM chat_threads('thread',0,1,'{b}')")) == '1'
assert run(f"SELECT count(*) FROM chat_messages WHERE conversation_id='{thread}'")=='4'
assert run(f"SELECT count(*) FROM chat_conversations WHERE initiator_id='{a}' AND recipient_id='{b}'")=='1'
legacy=run(actor(c,f"SELECT id FROM chat_conversations WHERE recipient_id='{d}'"))
run(block(c,d))
run(unblock(c,d))
run(reconnect(c,legacy),'55000')

def eligible(x,y):
    t=run(actor(x,f"SELECT chat_introduce('{y}','original')"))
    run(block(x,y))
    run(unblock(x,y))
    return t

second=eligible(a,c)
run(reconnect(a,second,' '),'23514')
race(reconnect(a,second),reconnect(a,second),'55000')
run(respond(c,False,second))
run(block(c,a))
run(unblock(c,a))
run(reconnect(c,second),'55000')
run(actor(c,f"SELECT chat_introduce('{a}','retry')"),'55000')
run(send(c,second),'55000')
third=eligible(b,d)
race(block(d,b),reconnect(b,third),'55000')
run(unblock(d,b))
run(reconnect(b,third),'55000')
race(reconnect(d,third),block(b,d))
run(unblock(b,d))
run(reconnect(b,third),'55000')
run(respond(b,True,third),'55000')
run("SET ROLE anon; SELECT chat_reconnect(NULL,NULL);",'42501')
run(actor(c,"SELECT count(*) FROM chat_reconnections"),'42501')
run("SET ROLE anon; SELECT chat_threads('inbox');",'42501')
print('Reconnection transitions, four lock-wait races, stale response rejection, participant reads, inbox history and hide cursor passed.')
