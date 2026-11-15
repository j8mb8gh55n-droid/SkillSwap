SELECT to_regprocedure('public.chat_set_muted(uuid,boolean)') AS mute_rpc,
       to_regprocedure('public.chat_hide(uuid)') AS hide_rpc,
       to_regclass('public.chat_visible_inbox') AS inbox_view,
       to_regprocedure('public.chat_unblock(uuid)') AS unblock_rpc,
       to_regprocedure('public.chat_report(uuid,text,bigint)') AS report_rpc,
       to_regprocedure('public.chat_finalize_attachment(uuid,uuid,uuid,text,integer)') AS attachment_rpc;
SELECT c.relname, c.relrowsecurity, p.policyname
FROM pg_class c
LEFT JOIN pg_policies p ON p.schemaname = 'public' AND p.tablename = c.relname
WHERE c.relnamespace = 'public'::regnamespace AND c.relname IN (
    'chat_conversation_preferences', 'chat_student_blocks', 'chat_legacy_blocks',
    'chat_reports', 'chat_message_attachments'
);
SELECT p.oid::regprocedure AS rpc, p.prosecdef, p.proconfig,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anonymous_execute,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS participant_execute,
       has_function_privilege('service_role',p.oid,'EXECUTE') AS service_execute
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN (
    'chat_set_muted', 'chat_hide', 'chat_block', 'chat_unblock', 'chat_report', 'chat_finalize_attachment'
);
SELECT public, file_size_limit, allowed_mime_types FROM storage.buckets WHERE id = 'chat-attachments';
SELECT policyname, cmd, roles
FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects';
