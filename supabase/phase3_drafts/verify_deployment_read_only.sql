-- 01: expect one valid unique index over requester_id and recipient_id for pending rows.
SELECT i.indisvalid, i.indisunique, pg_get_indexdef(i.indexrelid) AS definition
FROM pg_catalog.pg_index i
WHERE i.indexrelid = to_regclass('public.exchanges_one_pending_per_pair_idx');

-- 02: expect both client flags false and all five trigger owners able to execute.
SELECT has_function_privilege('anon', helper.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', helper.oid, 'EXECUTE') AS authenticated_execute,
       caller.oid::regprocedure AS caller,
       caller.prosecdef AS security_definer,
       has_function_privilege(caller.proowner, helper.oid, 'EXECUTE') AS owner_can_execute
FROM pg_catalog.pg_proc helper CROSS JOIN pg_catalog.pg_proc caller
WHERE helper.oid = 'public.notify(uuid,uuid,text,uuid,uuid,text)'::regprocedure
  AND caller.oid IN ('public.notifications_on_exchange_insert()'::regprocedure,
                    'public.notifications_on_exchange_update()'::regprocedure,
                    'public.notifications_on_session_insert()'::regprocedure,
                    'public.notifications_on_session_update()'::regprocedure,
                    'public.notifications_on_kudos_insert()'::regprocedure)
ORDER BY caller.oid::regprocedure;

-- 03: expect two enabled validation triggers, one for inserts and one for confirmation.
SELECT tgname, tgenabled, pg_get_triggerdef(oid) AS definition
FROM pg_catalog.pg_trigger
WHERE tgrelid = 'public.sessions'::regclass
  AND tgname IN ('validate_session_booking_insert_t', 'validate_session_booking_confirm_t')
ORDER BY tgname;

-- 04: expect both new triggers enabled, the replacement FK validated, and a valid unique index.
SELECT tgrelid::regclass AS relation, tgname, tgenabled, pg_get_triggerdef(oid) AS definition
FROM pg_catalog.pg_trigger
WHERE (tgrelid = 'public.sessions'::regclass AND tgname = 'zz_coordinate_session_booking_t')
   OR (tgrelid = 'public.exchanges'::regclass AND tgname = 'zz_close_exchange_sessions_t');

SELECT convalidated, pg_get_constraintdef(oid) AS definition
FROM pg_catalog.pg_constraint
WHERE conrelid = 'public.sessions'::regclass AND conname = 'sessions_replaces_session_id_fkey';

SELECT indisvalid, indisunique, pg_get_indexdef(indexrelid) AS definition
FROM pg_catalog.pg_index
WHERE indexrelid = to_regclass('public.sessions_one_confirmed_per_exchange_idx');

SELECT pg_get_functiondef('public.notifications_on_session_update()'::regprocedure)
       AS session_notification_definition;
