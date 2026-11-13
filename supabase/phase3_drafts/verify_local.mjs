import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const runtime = process.argv[2];
if (!runtime) throw new Error('Pass the absolute path to the temporary PGlite entry point.');
const { PGlite } = await import(pathToFileURL(runtime));
const db = new PGlite();
const alice = '00000000-0000-0000-0000-000000000001';
const bob = '00000000-0000-0000-0000-000000000002';
const exchange = '00000000-0000-0000-0000-000000000010';

const sql = (text) => db.exec(text);
const rows = async (text) => (await db.query(text)).rows;
const count = async (text, expected) => {
    assert.equal(Number((await rows(text))[0].count), expected);
};
const actor = (id) => sql(`RESET ROLE; SELECT set_config('request.jwt.claim.sub', '${id}', false); SET ROLE authenticated;`);
const load = async (path) => {
    const script = await readFile(new URL(path, import.meta.url), 'utf8');
    await sql(script.replace(/create extension if not exists pgcrypto;/ig, ''));
};

try {
    await sql(`
        CREATE ROLE anon;
        CREATE ROLE authenticated;
        CREATE SCHEMA auth;
        CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
        $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
        GRANT USAGE ON SCHEMA auth TO authenticated, anon;
        CREATE TABLE public.profiles (id uuid PRIMARY KEY);
        CREATE TABLE public.skills (id bigint PRIMARY KEY);
        CREATE TABLE public.student_skills (student_id uuid, skill_id bigint, skill_type text);
        INSERT INTO public.profiles VALUES ('${alice}'), ('${bob}');
        INSERT INTO public.skills VALUES (1), (2), (3);
        INSERT INTO public.student_skills VALUES
            ('${alice}',1,'teach'), ('${alice}',3,'teach'), ('${bob}',2,'teach');
    `);
    for (const file of ['phase2_exchanges', 'phase3_notifications', 'phase6_kudos',
                        'phase10_availability_status', 'phase11_kudos_notification']) {
        await load(`../${file}.sql`);
    }
    await sql(`GRANT EXECUTE ON FUNCTION public.notify(uuid,uuid,text,uuid,uuid,text) TO anon, authenticated;`);
    for (const file of ['01_pending_request_pair', '02_notification_helper_grants',
                        '03_session_validation', '04_atomic_rescheduling']) {
        await load(`./${file}.sql`);
    }

    await actor(alice);
    const request = (skill) => `INSERT INTO exchanges (requester_id, recipient_id, offered_skill_id, requested_skill_id)
        VALUES ('${alice}', '${bob}', ${skill}, 2)`;
    await sql(`INSERT INTO exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
               VALUES ('${exchange}','${alice}','${bob}',1,2)`);
    await assert.rejects(sql(request(3)), { code: '23505' });
    await assert.rejects(sql(`SELECT public.notify(NULL,NULL,NULL,NULL,NULL,NULL)`), { code: '42501' });
    await actor(bob);
    await count(`SELECT count(*) FROM notifications WHERE type = 'request_received'`, 1);
    await sql(`UPDATE exchanges SET status = 'accepted' WHERE id = '${exchange}'`);

    const propose = async (time, details) => (await rows(`
        INSERT INTO sessions (exchange_id, scheduled_at, format, proposed_by, location_or_link)
        VALUES ('${exchange}', ${time}, 'in_person', auth.uid(), ${details}) RETURNING id
    `))[0].id;
    const change = (id, status) => sql(`UPDATE sessions SET status = '${status}' WHERE id = '${id}'`);
    const future = "now() + interval '2 days'";
    await assert.rejects(propose("now() - interval '1 day'", "'Campus'"), { code: '23514' });
    await assert.rejects(propose(future, "'  '"), { code: '23514' });
    const original = await propose(future, "'Campus'");
    await assert.rejects(change(original, 'confirmed'), /other participant/);
    await actor(alice);
    await change(original, 'confirmed');
    const rejected = await propose(future, "'Library'");
    const replacement = await propose(future, "'Lab'");
    const stale = await propose(future, "'Cafe'");
    await actor(bob);
    await change(rejected, 'cancelled');
    await count(`SELECT count(*) FROM sessions WHERE id = '${original}' AND status = 'confirmed'`, 1);
    await change(replacement, 'confirmed');
    await change(replacement, 'confirmed');
    await assert.rejects(change(stale, 'confirmed'), /original booking changed/);
    await count(`SELECT count(*) FROM sessions WHERE status = 'confirmed'`, 1);
    await count(`SELECT count(*) FROM sessions WHERE id = '${original}' AND status = 'cancelled'`, 1);
    await actor(alice);
    await count(`SELECT count(*) FROM notifications WHERE session_id = '${replacement}'
                 AND type = 'session_confirmed' AND message LIKE '%rescheduled%'`, 1);
    await sql(`RESET ROLE`);
    await count(`SELECT count(*) FROM notifications WHERE session_id = '${original}'
                 AND type = 'session_cancelled'`, 0);
    await actor(alice);
    await propose(future, "'Studio'");
    await sql(`UPDATE exchanges SET status = 'cancelled' WHERE id = '${exchange}'`);
    await actor(bob);
    await count(`SELECT count(*) FROM sessions WHERE status <> 'cancelled'`, 0);
    await count(`SELECT count(*) FROM notifications WHERE type = 'exchange_cancelled'`, 1);
    console.log('Local PostgreSQL checks passed for drafts 01–04.');
} finally {
    await db.close();
}
