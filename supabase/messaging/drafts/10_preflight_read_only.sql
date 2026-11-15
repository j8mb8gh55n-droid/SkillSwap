SELECT current_setting('transaction_read_only') AS read_only,
 to_regclass('public.chat_reconnections') AS reconnections,
 to_regclass('public.chat_conversation_preferences') AS preferences,
 (SELECT jsonb_object_agg(p.proname,jsonb_build_object('definition',pg_get_functiondef(p.oid),'owner',pg_get_userbyid(p.proowner),'acl',p.proacl,'auth_exec',has_function_privilege('authenticated',p.oid,'EXECUTE'),'anon_exec',has_function_privilege('anon',p.oid,'EXECUTE'))) FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname LIKE 'chat_%') AS functions,
 (SELECT jsonb_object_agg(c.relname,jsonb_build_object('rls',c.relrowsecurity,'forced',c.relforcerowsecurity,'owner',pg_get_userbyid(c.relowner),'acl',c.relacl,'columns',(SELECT jsonb_object_agg(a.attname,a.attacl) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped))) FROM pg_class c WHERE c.oid IN ('public.chat_conversations'::regclass,'public.chat_messages'::regclass,'public.chat_student_blocks'::regclass,'public.chat_legacy_blocks'::regclass,'public.profiles'::regclass)) AS tables,
 (SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p WHERE schemaname='public' AND (tablename LIKE 'chat_%' OR tablename='profiles')) AS policies,
 (SELECT jsonb_agg(pg_get_constraintdef(k.oid) ORDER BY k.conname) FROM pg_constraint k WHERE k.conrelid IN ('public.chat_conversations'::regclass,'public.chat_messages'::regclass,'public.chat_student_blocks'::regclass,'public.chat_legacy_blocks'::regclass)) AS constraints,
 (SELECT jsonb_agg(jsonb_build_object('name',ic.relname,'definition',pg_get_indexdef(i.indexrelid),'valid',i.indisvalid,'ready',i.indisready)) FROM pg_index i JOIN pg_class ic ON ic.oid=i.indexrelid JOIN pg_class tc ON tc.oid=i.indrelid WHERE tc.relnamespace='public'::regnamespace AND tc.relname LIKE 'chat_%') AS indexes,
 (SELECT jsonb_agg(pg_get_triggerdef(t.oid)) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relnamespace='public'::regnamespace AND c.relname LIKE 'chat_%' AND NOT t.tgisinternal) AS custom_triggers,
 jsonb_build_object('conversations',(SELECT count(*) FROM public.chat_conversations),'messages',(SELECT count(*) FROM public.chat_messages),'owned_blocks',(SELECT count(*) FROM public.chat_student_blocks),'legacy_blocks',(SELECT count(*) FROM public.chat_legacy_blocks),'statuses',(SELECT jsonb_object_agg(status,n) FROM (SELECT status,count(*) AS n FROM public.chat_conversations GROUP BY status) s)) AS counts;

SELECT to_regprocedure('public.chat_reconnect(uuid,text)') AS reconnect,
       to_regprocedure('public.chat_respond_to_reconnection(uuid,bigint,boolean)') AS respond_to_reconnection,
       to_regprocedure('public.chat_threads(text,integer,integer,uuid)') AS threads,
       (SELECT indisunique AND indisvalid AND indisready FROM pg_index
        WHERE indexrelid = to_regclass('public.chat_conversations_pair_idx')) AS valid_pair_index,
       (SELECT count(*) FROM public.chat_messages m LEFT JOIN public.chat_conversations c ON c.id = m.conversation_id
        WHERE c.id IS NULL OR m.author_id NOT IN (c.initiator_id, c.recipient_id)) AS invalid_messages;
