SELECT c.relname, c.relrowsecurity,
       has_table_privilege('authenticated', c.oid, 'SELECT,INSERT,UPDATE,DELETE') AS client_access
FROM pg_class c WHERE c.oid = to_regclass('public.chat_reconnections');

SELECT p.oid::regprocedure, p.prosecdef, p.proconfig, p.proacl,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN
    ('chat_unblock', 'chat_respond', 'chat_reconnect', 'chat_respond_to_reconnection', 'chat_threads');

SELECT count(*) FILTER (WHERE r.requester_id NOT IN (c.initiator_id, c.recipient_id)
    OR (r.message_id IS NOT NULL AND (m.conversation_id IS DISTINCT FROM c.id OR m.author_id IS DISTINCT FROM r.requester_id))) AS invalid_reconnections
FROM public.chat_reconnections r
JOIN public.chat_conversations c ON c.id = r.conversation_id
LEFT JOIN public.chat_messages m ON m.id = r.message_id;

SELECT (SELECT count(*) FROM public.chat_conversations) AS conversations,
       (SELECT count(*) FROM public.chat_messages) AS messages,
       (SELECT count(*) FROM public.chat_student_blocks) AS owned_blocks,
       (SELECT count(*) FROM public.chat_legacy_blocks) AS legacy_blocks,
       (SELECT count(*) FROM public.chat_reconnections) AS reconnection_rows,
       (SELECT indisunique AND indisvalid AND indisready FROM pg_index
        WHERE indexrelid = to_regclass('public.chat_conversations_pair_idx')) AS valid_pair_index;

SELECT conname, convalidated, pg_get_constraintdef(oid) AS definition
FROM pg_constraint WHERE conrelid = to_regclass('public.chat_reconnections');
