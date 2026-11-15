-- Run as the deployment role in the target Dashboard before the first migration.
WITH expected_trigger(relation, trigger_name, handler) AS (
    VALUES
      ('public.exchanges', 'exchanges_guard_t', 'public.exchanges_guard()'),
      ('public.exchanges', 'exchanges_validate_insert_t', 'public.exchanges_validate_insert()'),
      ('public.exchanges', 'notifications_on_exchange_insert_t', 'public.notifications_on_exchange_insert()'),
      ('public.exchanges', 'notifications_on_exchange_update_t', 'public.notifications_on_exchange_update()'),
      ('public.sessions', 'sessions_guard_t', 'public.sessions_guard()'),
      ('public.sessions', 'sessions_validate_insert_t', 'public.sessions_validate_insert()'),
      ('public.sessions', 'notifications_on_session_insert_t', 'public.notifications_on_session_insert()'),
      ('public.sessions', 'notifications_on_session_update_t', 'public.notifications_on_session_update()'),
      ('public.kudos', 'notifications_on_kudos_insert_t', 'public.notifications_on_kudos_insert()')
)
SELECT
    (SELECT count(*) FROM (
        SELECT 1 FROM public.exchanges WHERE status = 'pending'
        GROUP BY requester_id, recipient_id HAVING count(*) > 1
    ) d) AS duplicate_pending_pairs,
    (SELECT count(*) FROM (
        SELECT 1 FROM public.sessions WHERE status = 'confirmed'
        GROUP BY exchange_id HAVING count(*) > 1
    ) d) AS exchanges_with_multiple_confirmed,
    (SELECT count(*) FROM public.sessions
     WHERE status = 'proposed' AND scheduled_at > statement_timestamp()
       AND nullif(btrim(location_or_link, E' \t\n\r'), '') IS NULL
    ) AS future_proposals_missing_details,
    (SELECT count(*) FROM public.sessions p
     WHERE p.status = 'proposed' AND p.scheduled_at > statement_timestamp()
       AND EXISTS (SELECT 1 FROM public.sessions c
                   WHERE c.exchange_id = p.exchange_id AND c.status = 'confirmed')
    ) AS future_proposals_with_existing_booking,
    (SELECT count(*) FROM public.sessions s JOIN public.exchanges e ON e.id = s.exchange_id
     WHERE e.status = 'cancelled'
       AND (s.status = 'proposed' OR
            (s.status = 'confirmed' AND s.scheduled_at > statement_timestamp()))
    ) AS open_sessions_on_cancelled_exchanges,
    ARRAY(SELECT trigger_name FROM expected_trigger e WHERE NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger t
        WHERE t.tgrelid = to_regclass(e.relation) AND t.tgname = e.trigger_name
          AND t.tgfoid = to_regprocedure(e.handler) AND t.tgenabled IN ('O', 'A')
    )) AS missing_or_disabled_triggers,
    to_regclass('public.exchanges_one_pending_per_pair_idx') IS NULL
      AND to_regclass('public.sessions_one_confirmed_per_exchange_idx') IS NULL
      AND to_regprocedure('public.validate_session_booking()') IS NULL
      AND to_regprocedure('public.coordinate_session_booking()') IS NULL
      AND to_regprocedure('public.close_exchange_sessions()') IS NULL
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute
                      WHERE attrelid = 'public.sessions'::regclass
                        AND attname = 'replaces_session_id' AND NOT attisdropped)
      AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger
                      WHERE tgrelid IN ('public.sessions'::regclass, 'public.exchanges'::regclass)
                        AND tgname IN ('validate_session_booking_insert_t',
                            'validate_session_booking_confirm_t',
                            'zz_coordinate_session_booking_t', 'zz_close_exchange_sessions_t'))
        AS new_names_available,
    current_setting('transaction_isolation') AS transaction_isolation;

-- Capture the current helper ACL, owners, and the exact function body draft 04 replaces.
SELECT p.oid::regprocedure AS routine, pg_get_userbyid(p.proowner) AS owner,
       p.proacl AS grants, p.prosecdef AS security_definer,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
       CASE WHEN p.proname = 'notifications_on_session_update'
            THEN pg_get_functiondef(p.oid) END AS rollback_definition
FROM pg_catalog.pg_proc p
WHERE p.oid IN (
    to_regprocedure('public.notify(uuid,uuid,text,uuid,uuid,text)'),
    to_regprocedure('public.notifications_on_exchange_insert()'),
    to_regprocedure('public.notifications_on_exchange_update()'),
    to_regprocedure('public.notifications_on_session_insert()'),
    to_regprocedure('public.notifications_on_session_update()'),
    to_regprocedure('public.notifications_on_kudos_insert()')
)
ORDER BY 1;
