SELECT n.nspname, c.relname, c.relrowsecurity, c.relacl,
       has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS student_access,
       has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS anonymous_access,
       has_table_privilege('service_role', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS service_access
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE (n.nspname = 'chat_moderation_private' AND c.relkind = 'r')
   OR c.oid = 'public.chat_reports'::regclass;

SELECT n.nspname, n.nspacl, has_schema_privilege('authenticated', n.oid, 'USAGE,CREATE') AS student_access
FROM pg_namespace n WHERE n.nspname = 'chat_moderation_private';

SELECT p.oid::regprocedure, pg_get_functiondef(p.oid) AS definition,
       pg_get_userbyid(p.proowner) AS owner, p.proacl, p.proconfig, p.prosecdef,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anonymous_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') AS service_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE (n.nspname = 'public' AND (p.proname = 'chat_report' OR p.proname LIKE 'chat_moderation_%'))
   OR (n.nspname = 'chat_moderation_private' AND p.proname = 'require_member');

SELECT schemaname, tablename, policyname FROM pg_policies
WHERE schemaname = 'chat_moderation_private' OR (schemaname = 'public' AND tablename = 'chat_reports');

SELECT (SELECT count(*) FROM chat_moderation_private.members WHERE revoked_at IS NULL) AS active_moderators,
       (SELECT count(*) FROM public.chat_reports) AS reports,
       (SELECT count(*) FROM chat_moderation_private.actions) AS audit_events;
