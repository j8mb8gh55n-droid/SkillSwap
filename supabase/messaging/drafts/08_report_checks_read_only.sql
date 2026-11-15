SELECT current_setting('server_version_num') AS server_version,
       to_regclass('public.chat_reports') AS report_table,
       to_regclass('public.chat_conversations') AS conversations,
       to_regclass('public.chat_messages') AS messages,
       to_regclass('public.chat_student_blocks') AS owned_blocks,
       to_regclass('public.chat_reconnections') AS reconnections;

SELECT p.oid::regprocedure AS signature, pg_get_functiondef(p.oid) AS definition,
       pg_get_userbyid(p.proowner) AS owner, p.proacl,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anonymous_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute
FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
AND p.proname IN ('chat_report', 'chat_block', 'chat_unblock', 'chat_reconnect');

SELECT c.relrowsecurity, c.relacl,
       has_table_privilege('anon', c.oid, 'SELECT,INSERT,UPDATE,DELETE') AS anonymous_access,
       has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE') AS client_access
FROM pg_class c WHERE c.oid = to_regclass('public.chat_reports');

SELECT policyname, roles, cmd FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'chat_reports';

SELECT conname, convalidated, pg_get_constraintdef(oid) AS definition
FROM pg_constraint WHERE conrelid = to_regclass('public.chat_reports');

SELECT (SELECT count(*) FROM public.chat_conversations) AS conversation_count,
       (SELECT count(*) FROM public.chat_messages) AS message_count;

SELECT count(*) AS report_count FROM public.chat_reports;

SELECT ic.relname, i.indisvalid, i.indisready, pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
WHERE i.indrelid = to_regclass('public.chat_reports');
