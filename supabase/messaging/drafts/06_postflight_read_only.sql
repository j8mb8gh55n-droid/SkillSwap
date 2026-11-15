SELECT jsonb_build_object(
    'objects', (SELECT jsonb_agg(jsonb_build_object('name',c.relname,'rls',c.relrowsecurity,
        'options',c.reloptions,'acl',c.relacl,'owner',pg_get_userbyid(c.relowner),
        'authenticated_select',has_table_privilege('authenticated',c.oid,'SELECT'),
        'authenticated_write',has_table_privilege('authenticated',c.oid,'INSERT,UPDATE,DELETE,TRUNCATE'),
        'anon_access',has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')))
        FROM pg_class c WHERE c.oid IN ('public.chat_conversation_preferences'::regclass,'public.chat_visible_inbox'::regclass)),
    'policies',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p WHERE p.schemaname='public'
        AND p.tablename='chat_conversation_preferences'),
    'view',pg_get_viewdef('public.chat_visible_inbox'::regclass,true),
    'rpcs',(SELECT jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object(
        'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl,
        'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
        'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')))
        FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname IN
        ('chat_threads','chat_send','chat_introduce','chat_respond','chat_unread_counts','chat_mark_read','chat_block',
         'chat_unblock','chat_reconnect','chat_respond_to_reconnection','chat_report','chat_hide','chat_set_muted')),
    'constraints',(SELECT jsonb_object_agg(conname,jsonb_build_object('definition',pg_get_constraintdef(oid),'validated',convalidated))
        FROM pg_constraint WHERE conrelid='public.chat_conversation_preferences'::regclass),
    'valid_preferences_key',(SELECT indisprimary AND indisunique AND indisvalid AND indisready FROM pg_index
        WHERE indexrelid=to_regclass('public.chat_conversation_preferences_pkey')),
    'valid_pair_index',(SELECT indisunique AND indisvalid AND indisready FROM pg_index
        WHERE indexrelid=to_regclass('public.chat_conversations_pair_idx')),
    'counts',jsonb_build_object('preferences',(SELECT count(*) FROM public.chat_conversation_preferences),
        'conversations',(SELECT count(*) FROM public.chat_conversations),'messages',(SELECT count(*) FROM public.chat_messages),
        'reports',(SELECT count(*) FROM public.chat_reports),'reconnections',(SELECT count(*) FROM public.chat_reconnections),
        'owned_blocks',(SELECT count(*) FROM public.chat_student_blocks),'legacy_blocks',(SELECT count(*) FROM public.chat_legacy_blocks))
) AS migration_06_postflight;
