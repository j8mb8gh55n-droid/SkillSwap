SELECT jsonb_build_object(
    'version', current_setting('server_version_num'),
    'operator', current_user,
    'can_create', has_schema_privilege(current_user, 'public', 'CREATE'),
    'auth_uid', to_regprocedure('auth.uid()'),
    'targets', ARRAY(SELECT relname FROM pg_class WHERE relnamespace='public'::regnamespace
        AND relname IN ('chat_conversation_preferences','chat_conversation_preferences_pkey','chat_visible_inbox')),
    'types', ARRAY(SELECT typname FROM pg_type WHERE typnamespace='public'::regnamespace
        AND typname IN ('chat_conversation_preferences','chat_visible_inbox')),
    'rpcs', (SELECT jsonb_object_agg(p.oid::regprocedure::text, jsonb_build_object(
        'definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl,
        'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
        'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE')))
        FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname IN
        ('chat_threads','chat_send','chat_introduce','chat_respond','chat_unread_counts','chat_mark_read','chat_block',
         'chat_unblock','chat_reconnect','chat_respond_to_reconnection','chat_report','chat_hide','chat_set_muted')),
    'client_roles', (SELECT jsonb_agg(jsonb_build_object(
        'role', r.rolname, 'superuser',r.rolsuper, 'bypass_rls',r.rolbypassrls,
        'memberships',ARRAY(SELECT g.rolname FROM pg_roles g WHERE g.oid<>r.oid
            AND (pg_has_role(r.oid,g.oid,'USAGE') OR pg_has_role(r.oid,g.oid,'SET')))))
        FROM pg_roles r WHERE r.rolname IN ('anon','authenticated')),
    'defaults', (SELECT jsonb_agg(to_jsonb(a)) FROM pg_default_acl a
        WHERE defaclrole=current_user::regrole AND defaclnamespace IN (0,'public'::regnamespace)),
    'tables', (SELECT jsonb_object_agg(c.relname,jsonb_build_object('rls',c.relrowsecurity,
        'owner',pg_get_userbyid(c.relowner),'acl',c.relacl,
        'column_acl',(SELECT jsonb_object_agg(a.attname,a.attacl) FROM pg_attribute a
                      WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped)))
        FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relname IN
        ('profiles','chat_conversations','chat_messages','chat_student_blocks','chat_legacy_blocks','chat_reports','chat_reconnections')),
    'policies', (SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p WHERE schemaname='public'
        AND (tablename LIKE 'chat_%' OR tablename='profiles')),
    'valid_pair_index',(SELECT indisvalid AND indisunique AND indisready FROM pg_index
        WHERE indexrelid=to_regclass('public.chat_conversations_pair_idx')),
    'counts',jsonb_build_object('conversations',(SELECT count(*) FROM public.chat_conversations),
        'messages',(SELECT count(*) FROM public.chat_messages),'reports',(SELECT count(*) FROM public.chat_reports),
        'reconnections',(SELECT count(*) FROM public.chat_reconnections),
        'owned_blocks',(SELECT count(*) FROM public.chat_student_blocks),
        'legacy_blocks',(SELECT count(*) FROM public.chat_legacy_blocks))
) AS migration_06_preflight;
