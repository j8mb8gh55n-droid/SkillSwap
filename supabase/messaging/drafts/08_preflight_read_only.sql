SELECT jsonb_build_object(
    'server_version_num', current_setting('server_version_num')::integer,
    'operator', current_user,
    'can_create_in_public', has_schema_privilege(current_user, 'public', 'CREATE'),
    'report_table', to_regclass('public.chat_reports'),
    'report_index', to_regclass('public.chat_reports_reporter_created_idx'),
    'moderation_schema', to_regnamespace('chat_moderation_private'),
    'auth_uid', to_regprocedure('auth.uid()'),
    'required_tables', jsonb_build_object(
        'profiles', to_regclass('public.profiles'),
        'conversations', to_regclass('public.chat_conversations'),
        'messages', to_regclass('public.chat_messages'),
        'owned_blocks', to_regclass('public.chat_student_blocks'),
        'reconnections', to_regclass('public.chat_reconnections')
    ),
    'reporting_rpcs', (SELECT coalesce(jsonb_agg(p.oid::regprocedure::text), '[]'::jsonb)
        FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
        AND (p.proname = 'chat_report' OR p.proname LIKE 'chat_moderation_%')),
    'existing_rpc_metadata', (SELECT jsonb_object_agg(p.oid::regprocedure::text,
        jsonb_build_object('owner', pg_get_userbyid(p.proowner), 'acl', p.proacl,
            'definition', pg_get_functiondef(p.oid)))
        FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
        AND p.proname IN ('chat_send', 'chat_block', 'chat_unblock', 'chat_reconnect',
                          'chat_respond', 'chat_respond_to_reconnection', 'chat_threads')),
    'default_acl', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'type', d.defaclobjtype, 'schema', n.nspname, 'grants', d.defaclacl)), '[]'::jsonb)
        FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
        WHERE d.defaclrole = current_user::regrole AND (d.defaclnamespace = 0 OR n.nspname = 'public')),
    'counts', jsonb_build_object('conversations', (SELECT count(*) FROM public.chat_conversations),
                                 'messages', (SELECT count(*) FROM public.chat_messages))
) AS migration_08_preflight;
