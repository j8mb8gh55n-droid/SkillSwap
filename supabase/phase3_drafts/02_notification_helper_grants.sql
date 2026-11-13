-- Review and rehearse in staging before applying.
BEGIN;

REVOKE EXECUTE ON FUNCTION public.notify(uuid, uuid, text, uuid, uuid, text)
    FROM PUBLIC, anon, authenticated;

DO $$
DECLARE
    helper oid := 'public.notify(uuid, uuid, text, uuid, uuid, text)'::regprocedure;
BEGIN
    IF has_function_privilege('anon', helper, 'EXECUTE')
       OR has_function_privilege('authenticated', helper, 'EXECUTE') THEN
        RAISE EXCEPTION 'Client execution of notify is still granted through another role';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname IN (
            'notifications_on_exchange_insert', 'notifications_on_exchange_update',
            'notifications_on_session_insert', 'notifications_on_session_update',
            'notifications_on_kudos_insert'
          )
          AND (NOT p.prosecdef OR NOT has_function_privilege(p.proowner, helper, 'EXECUTE'))
    ) THEN
        RAISE EXCEPTION 'A notification trigger function may lose access to notify';
    END IF;
END;
$$;

COMMIT;
