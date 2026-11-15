SELECT c.relname, c.relrowsecurity, p.polname, pg_get_expr(p.polqual, p.polrelid) AS predicate,
       has_table_privilege('authenticated', c.oid, 'INSERT') AS client_insert,
       has_table_privilege('authenticated', c.oid, 'UPDATE') AS client_update,
       has_table_privilege('authenticated', c.oid, 'DELETE') AS client_delete
FROM pg_class c LEFT JOIN pg_policy p ON p.polrelid = c.oid
WHERE c.oid IN ('public.chat_conversations'::regclass, 'public.chat_messages'::regclass);

SELECT has_column_privilege('authenticated','public.chat_conversations',
                            'initiator_read_through','SELECT') AS client_reads_initiator_cursor,
       has_column_privilege('authenticated','public.chat_conversations',
                            'recipient_read_through','SELECT') AS client_reads_recipient_cursor,
       i.indisvalid, i.indisunique, pg_get_indexdef(i.indexrelid) AS pair_index
FROM pg_index i WHERE i.indexrelid = 'public.chat_conversations_pair_idx'::regclass;

SELECT p.oid::regprocedure AS rpc, p.prosecdef, p.proconfig,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN (
    'chat_introduce', 'chat_respond', 'chat_send', 'chat_block',
    'chat_mark_read', 'chat_unread_counts'
) ORDER BY 1;

SELECT count(*) FILTER (WHERE c.status = 'pending' AND m.total <> 1) AS invalid_pending_threads,
       count(*) FILTER (WHERE m.outsiders > 0) AS threads_with_invalid_authors
FROM public.chat_conversations c
CROSS JOIN LATERAL (
    SELECT count(*) AS total,
           count(*) FILTER (WHERE author_id NOT IN (c.initiator_id, c.recipient_id)) AS outsiders
    FROM public.chat_messages WHERE conversation_id = c.id
) m;
