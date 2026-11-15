SELECT current_setting('server_version_num')::integer AS version,
       to_regnamespace('chat_moderation_private') AS moderation_schema,
       to_regclass('public.chat_reports') AS reports,
       ARRAY(SELECT n.nspname || '.' || c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname NOT IN ('pg_catalog', 'information_schema') AND c.relkind IN ('r', 'v', 'p')
               AND c.relname ~* '(moderat|admin|role|report)') AS authorization_objects,
       ARRAY(SELECT p.oid::regprocedure::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.proname ~* '(moderat|admin|report)') AS authorization_rpcs,
       ARRAY(SELECT DISTINCT key FROM auth.users
             CROSS JOIN LATERAL jsonb_object_keys(coalesce(raw_app_meta_data, '{}'::jsonb)) AS k(key)
             WHERE key ~* '(role|admin|moderat)') AS app_metadata_key_names;
