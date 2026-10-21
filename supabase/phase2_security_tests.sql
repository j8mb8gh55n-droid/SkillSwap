-- ============================================================================
-- SkillSwap — Phase 2 security test plan  (REVISED, non-destructive by design)
-- ----------------------------------------------------------------------------
-- Companion to phase2_exchanges.sql. DO NOT run automatically. Run sections
-- MANUALLY, by hand, after the migration is applied — ideally on a disposable
-- / staging project.
--
-- SAFETY MODEL:
--   * SECTION R  — READ-ONLY catalog checks. Pure SELECTs. Cannot alter data.
--   * (hard safety stop)
--   * SECTION T  — TRANSACTIONAL behavior tests. EVERY test is wrapped in
--                  BEGIN ... ROLLBACK and contains NO COMMIT, so nothing it
--                  does is ever persisted — even the "success" paths roll back.
--   * SECTION B  — AUTHENTICATED-SESSION / concurrency tests. Described as
--                  REST/app steps; not executable here (need real JWTs).
--
-- Because SECTION T never commits, it is safe against production data; the
-- safety stop below is an additional gate so a careless "run whole file" does
-- not reach SECTION T at all.
--
-- Impersonation (SECTION T): inside each transaction,
--     set local role authenticated;
--     set local request.jwt.claims = '{"sub":"<UUID>","role":"authenticated"}';
-- auth.uid() reads request.jwt.claims->>'sub'. Switching the acting user is
-- just re-SETting the claims within the same transaction.
--
-- Replace placeholders with real rows from your project before running:
--   ALICE_UUID            profiles.id — requester
--   BOB_UUID              profiles.id — recipient (different person)
--   CAROL_UUID            profiles.id — unrelated outsider
--   SKILL_ALICE_TEACHES   skills.id that Alice has as student_skills(skill_type='teach')
--   SKILL_BOB_TEACHES     skills.id that Bob   has as student_skills(skill_type='teach')
-- ============================================================================


-- ============================================================================
-- SECTION R — READ-ONLY VERIFICATION (safe; alters nothing)
-- ============================================================================

-- R1. RLS is enabled on both new tables (expect relrowsecurity = true).
select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('exchanges','sessions');

-- R2. Policies exist and are scoped (expect 3 on exchanges, 3 on sessions).
select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('exchanges','sessions')
order by tablename, cmd, policyname;

-- R3. Duplicate-pending unique index exists and is partial.
select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'exchanges'
  and indexname = 'exchanges_unique_pending_idx';

-- R4. Trigger functions have the expected security + hardened search_path.
--     Expect: validate_insert = DEFINER; guards = INVOKER; all search_path=''.
select p.proname,
       case when p.prosecdef then 'DEFINER' else 'INVOKER' end as security,
       p.proconfig
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('exchanges_validate_insert','exchanges_guard',
                    'sessions_validate_insert','sessions_guard');

-- R5. EXECUTE has been revoked from PUBLIC on the trigger functions
--     (expect no row granting EXECUTE to PUBLIC / role 'public').
select p.proname, coalesce(array_to_string(p.proacl, ' '), '(default)') as acl
from pg_proc p
where p.pronamespace = 'public'::regnamespace
  and p.proname in ('exchanges_validate_insert','exchanges_guard',
                    'sessions_validate_insert','sessions_guard');

-- R6. Triggers are attached as expected.
select tgrelid::regclass as table, tgname, tgenabled
from pg_trigger
where tgrelid in ('public.exchanges'::regclass,'public.sessions'::regclass)
  and not tgisinternal
order by 1, 2;

-- R7. Foreign keys reference the EXISTING tables (compatibility check).
select conrelid::regclass as child, conname,
       confrelid::regclass as parent
from pg_constraint
where contype = 'f'
  and conrelid in ('public.exchanges'::regclass,'public.sessions'::regclass)
order by 1, 2;

-- R8. Existing tables untouched — confirm the four originals still exist with
--     RLS on (spot check; this migration must not have modified them).
select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace
  and relname in ('profiles','skills','student_skills','availability');


-- ============================================================================
-- >>> HARD SAFETY STOP <<<
-- The block below intentionally raises so that running the ENTIRE file top to
-- bottom halts here, before any SECTION T test. To run SECTION T, execute the
-- individual BEGIN...ROLLBACK blocks by hand (and, if you like, delete this).
-- ============================================================================
do $$
begin
    raise exception
        'SAFETY STOP: SECTION T below is for MANUAL, per-block execution only. '
        'Each block is BEGIN...ROLLBACK (non-persisting). Run them one at a time.';
end
$$;


-- ============================================================================
-- SECTION T — TRANSACTIONAL TESTS (each block is self-contained; ends in
--             ROLLBACK; NO COMMIT anywhere -> nothing is persisted)
-- ============================================================================

-- --- T1. Self-exchange rejected (req 1). EXPECT: ERROR (exchanges_not_self) ---
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('ALICE_UUID','ALICE_UUID', SKILL_ALICE_TEACHES, SKILL_ALICE_TEACHES);
rollback;

-- --- T2. Offered skill must be really taught (req 7). EXPECT: ERROR ----------
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('ALICE_UUID','BOB_UUID', 999999, SKILL_BOB_TEACHES);   -- 999999 = not Alice's
rollback;

-- --- T3. Duplicate pending request rejected (req 5). EXPECT: ERROR on 2nd ----
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  insert into public.exchanges (requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);   -- duplicate
rollback;

-- --- T4. Requester cannot accept own request (req 2). EXPECT: ERROR ----------
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('11111111-1111-1111-1111-111111111111','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  update public.exchanges set status='accepted'
   where id='11111111-1111-1111-1111-111111111111';     -- actor is Alice (requester) -> ERROR
rollback;

-- --- T5. Recipient accepts (req 2). EXPECT: success; responded_at set --------
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('22222222-2222-2222-2222-222222222222','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted'
   where id='22222222-2222-2222-2222-222222222222';
  select status, responded_at is not null as responded
    from public.exchanges where id='22222222-2222-2222-2222-222222222222';  -- EXPECT accepted, true
rollback;

-- --- T6. Exchange metadata immutable (req 3). EXPECT: ERROR ------------------
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id, message)
  values ('33333333-3333-3333-3333-333333333333','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES, 'hi');
  update public.exchanges set message='edited'
   where id='33333333-3333-3333-3333-333333333333';   -- ERROR: details immutable
rollback;

-- --- T7. Participants/skills immutable (req 6). EXPECT: ERROR ----------------
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('44444444-4444-4444-4444-444444444444','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  update public.exchanges set requested_skill_id = SKILL_ALICE_TEACHES
   where id='44444444-4444-4444-4444-444444444444';   -- ERROR: identifiers immutable
rollback;

-- --- T8. New session can't start confirmed (req 1-sessions). EXPECT proposed -
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('55555555-5555-5555-5555-555555555555','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted' where id='55555555-5555-5555-5555-555555555555';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.sessions (exchange_id, scheduled_at, format, status, proposed_by)
  values ('55555555-5555-5555-5555-555555555555', now() + interval '1 day', 'online', 'confirmed', 'ALICE_UUID');
  select status from public.sessions where exchange_id='55555555-5555-5555-5555-555555555555';  -- EXPECT 'proposed'
rollback;

-- --- T9. Proposer cannot confirm own session (req 9). EXPECT: ERROR ----------
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('66666666-6666-6666-6666-666666666666','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted' where id='66666666-6666-6666-6666-666666666666';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.sessions (id, exchange_id, scheduled_at, format, proposed_by)
  values ('66660000-0000-0000-0000-000000000001','66666666-6666-6666-6666-666666666666', now() + interval '1 day', 'online', 'ALICE_UUID');
  update public.sessions set status='confirmed'
   where id='66660000-0000-0000-0000-000000000001';   -- actor Alice = proposer -> ERROR
rollback;

-- --- T10. The other participant confirms (req 9). EXPECT: success ------------
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('77777777-7777-7777-7777-777777777777','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted' where id='77777777-7777-7777-7777-777777777777';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.sessions (id, exchange_id, scheduled_at, format, proposed_by)
  values ('77770000-0000-0000-0000-000000000001','77777777-7777-7777-7777-777777777777', now() + interval '1 day', 'online', 'ALICE_UUID');
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.sessions set status='confirmed' where id='77770000-0000-0000-0000-000000000001';
  select status from public.sessions where id='77770000-0000-0000-0000-000000000001';  -- EXPECT 'confirmed'
rollback;

-- --- T11. Session details immutable (req 2-protect). EXPECT: ERROR -----------
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('88888888-8888-8888-8888-888888888888','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted' where id='88888888-8888-8888-8888-888888888888';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.sessions (id, exchange_id, scheduled_at, format, proposed_by)
  values ('88880000-0000-0000-0000-000000000001','88888888-8888-8888-8888-888888888888', now() + interval '1 day', 'online', 'ALICE_UUID');
  update public.sessions set scheduled_at = now() + interval '2 days'
   where id='88880000-0000-0000-0000-000000000001';   -- ERROR: details immutable
rollback;

-- --- T12. Forging the other's completion flag (req 11). EXPECT: ERROR --------
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('99999999-9999-9999-9999-999999999999','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted' where id='99999999-9999-9999-9999-999999999999';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  update public.exchanges set recipient_completed = true      -- Alice forging Bob's flag
   where id='99999999-9999-9999-9999-999999999999';          -- ERROR
rollback;

-- --- T13. Completion blocked without an eligible (past, confirmed) session ---
--     (req 10). Session here is in the FUTURE. EXPECT: ERROR
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('aaaaaaaa-0000-0000-0000-000000000001','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted' where id='aaaaaaaa-0000-0000-0000-000000000001';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.sessions (id, exchange_id, scheduled_at, format, proposed_by)
  values ('aaaa0000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001', now() + interval '1 day', 'online', 'ALICE_UUID');
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.sessions set status='confirmed' where id='aaaa0000-0000-0000-0000-000000000001';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  update public.exchanges set requester_completed = true
   where id='aaaaaaaa-0000-0000-0000-000000000001';   -- ERROR: session not yet occurred
rollback;

-- --- T14. Mutual completion success (reqs 10,12). Uses a PAST confirmed -------
--     session (proposed with a past scheduled_at — the DB allows it; only the
--     app UI requires future). EXPECT: success, exchange ends 'completed'.
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('bbbbbbbb-0000-0000-0000-000000000001','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted' where id='bbbbbbbb-0000-0000-0000-000000000001';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.sessions (id, exchange_id, scheduled_at, format, proposed_by)
  values ('bbbb0000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001', now() - interval '1 hour', 'online', 'ALICE_UUID');
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.sessions set status='confirmed' where id='bbbb0000-0000-0000-0000-000000000001';
  -- Alice confirms completion (stays accepted)
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  update public.exchanges set requester_completed = true where id='bbbbbbbb-0000-0000-0000-000000000001';
  select status, requester_completed, recipient_completed
    from public.exchanges where id='bbbbbbbb-0000-0000-0000-000000000001';  -- EXPECT accepted,t,f
  -- Bob confirms completion (trigger flips to completed)
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set recipient_completed = true where id='bbbbbbbb-0000-0000-0000-000000000001';
  select status, completed_at is not null as done
    from public.exchanges where id='bbbbbbbb-0000-0000-0000-000000000001';  -- EXPECT completed,true
rollback;

-- --- T15. Completed exchange is frozen (req 12). EXPECT: ERROR on final edit -
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('cccccccc-0000-0000-0000-000000000001','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted' where id='cccccccc-0000-0000-0000-000000000001';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.sessions (id, exchange_id, scheduled_at, format, proposed_by)
  values ('cccc0000-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000001', now() - interval '1 hour', 'online', 'ALICE_UUID');
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.sessions set status='confirmed' where id='cccc0000-0000-0000-0000-000000000001';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  update public.exchanges set requester_completed = true where id='cccccccc-0000-0000-0000-000000000001';
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set recipient_completed = true where id='cccccccc-0000-0000-0000-000000000001';  -- now completed
  update public.exchanges set status='accepted' where id='cccccccc-0000-0000-0000-000000000001';           -- ERROR: frozen
rollback;

-- --- T16. Session on a completed exchange is frozen (req 4). EXPECT: ERROR ---
begin;
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.exchanges (id, requester_id, recipient_id, offered_skill_id, requested_skill_id)
  values ('dddddddd-0000-0000-0000-000000000001','ALICE_UUID','BOB_UUID', SKILL_ALICE_TEACHES, SKILL_BOB_TEACHES);
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set status='accepted' where id='dddddddd-0000-0000-0000-000000000001';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  insert into public.sessions (id, exchange_id, scheduled_at, format, proposed_by)
  values ('dddd0000-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001', now() - interval '1 hour', 'online', 'ALICE_UUID');
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.sessions set status='confirmed' where id='dddd0000-0000-0000-0000-000000000001';
  set local request.jwt.claims = '{"sub":"ALICE_UUID","role":"authenticated"}';
  update public.exchanges set requester_completed = true where id='dddddddd-0000-0000-0000-000000000001';
  set local request.jwt.claims = '{"sub":"BOB_UUID","role":"authenticated"}';
  update public.exchanges set recipient_completed = true where id='dddddddd-0000-0000-0000-000000000001';  -- completed
  update public.sessions set status='cancelled' where id='dddd0000-0000-0000-0000-000000000001';           -- ERROR: parent not accepted
rollback;


-- ============================================================================
-- SECTION B — AUTHENTICATED-SESSION & CONCURRENCY TESTS (manual; real JWTs)
-- ----------------------------------------------------------------------------
-- RLS + auth.uid() are only faithfully exercised through genuine signed-in
-- sessions (the SQL Editor runs as a privileged role). Run via the REST API or
-- two app instances. Prereq: two confirmed accounts (Alice, Bob) each with a
-- 'teach' skill, plus a third account (Carol).
--
-- B1. Access isolation (req 5):
--     As Carol: GET /rest/v1/exchanges?id=eq.<Alice/Bob exchange> -> empty.
--     As Carol: PATCH that exchange -> 0 rows / 403.
--
-- B2. Insert authorization:
--     As Bob: POST exchange with requester_id = Alice -> rejected (with check
--     requires requester_id = auth.uid()).
--
-- B3. Propose-session authorization (req 8):
--     As Carol: POST session for Alice/Bob's accepted exchange -> rejected.
--     As Alice: POST session (proposed_by = Alice) on the accepted exchange
--       -> success, status 'proposed'.
--
-- B4. Confirm-by-other end to end (req 9):
--     As Alice (proposer): PATCH session -> 'confirmed' -> rejected.
--     As Bob: PATCH session -> 'confirmed' -> success.
--
-- B5. Mutual completion end to end (req 10): with an eligible (confirmed, past)
--     session, Alice PATCH requester_completed=true (success, still accepted);
--     Bob PATCH recipient_completed=true (success, now completed). Each setting
--     the other's flag -> rejected.
--
-- B6. History integrity (reqs 12,13): DELETE on exchanges/sessions -> 403 (no
--     grant); PATCH on a completed exchange -> rejected.
--
-- B7. CONCURRENCY — completion vs cancellation (req 2 fix):
--     Set up an accepted exchange with a confirmed, past session and ONE flag
--     already set. Then fire simultaneously:
--       (i)  Bob: PATCH recipient_completed = true  (completes the exchange)
--       (ii) Alice: PATCH the session -> 'cancelled'
--     EXPECT exactly one outcome wins, with no inconsistent state:
--       * if completion commits first, the cancel fails (parent no longer
--         'accepted');
--       * if the cancel commits first, completion fails ('requires a confirmed
--         session that has already taken place').
--     Repeat with both completion PATCHes fired simultaneously: EXPECT exactly
--     one 'completed' row, completed_at stamped once (row-lock serialization).
-- ============================================================================

-- No cleanup section is needed: SECTION R is read-only and SECTION T never
-- commits. SECTION B operates on real accounts — remove any rows it creates
-- from your staging project manually if desired.
