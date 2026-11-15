-- Read-only verification. Also rerun the preflight to compare existing objects.
WITH targets AS (
    SELECT c.oid, c.relname, c.relrowsecurity, c.relacl, pg_get_userbyid(c.relowner) AS owner
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public'
      AND c.relname IN ('community_posts','community_post_skills','community_saved_posts')
), rpc AS (
    SELECT pg_get_functiondef(p.oid) AS definition, pg_get_userbyid(p.proowner) AS owner,
           p.prosecdef, p.proconfig, p.proacl,
           has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
           has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
           EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a
                   WHERE a.grantee=0 AND a.privilege_type='EXECUTE') AS public_execute
    FROM pg_proc p WHERE p.oid=to_regprocedure(
        'public.community_save_post(text,text,text,bigint[],text,uuid)')
), access AS (
    SELECT t.relname, role_name,
           has_any_column_privilege(role_name,t.oid,'SELECT') AS can_select,
           has_any_column_privilege(role_name,t.oid,'INSERT') AS can_insert,
           has_any_column_privilege(role_name,t.oid,'UPDATE') AS can_update,
           has_table_privilege(role_name,t.oid,'DELETE') AS can_delete,
           has_table_privilege(role_name,t.oid,'TRUNCATE') AS can_truncate
    FROM targets t CROSS JOIN (VALUES ('anon'),('authenticated')) r(role_name)
)
SELECT jsonb_build_object(
    'tables', (SELECT jsonb_agg(to_jsonb(t)-'oid' ORDER BY relname) FROM targets t),
    'policies', (SELECT jsonb_agg(to_jsonb(p) ORDER BY tablename,policyname) FROM pg_policies p
                 WHERE schemaname='public' AND tablename IN (SELECT relname FROM targets)),
    'access', (SELECT jsonb_agg(to_jsonb(a) ORDER BY relname,role_name) FROM access a),
    'bookmark_columns', (SELECT jsonb_object_agg(a.attname,
                                  has_column_privilege('authenticated',t.oid,a.attnum,'INSERT'))
                         FROM targets t JOIN pg_attribute a ON a.attrelid=t.oid
                         WHERE t.relname='community_saved_posts' AND a.attnum>0 AND NOT a.attisdropped),
    'rpc', (SELECT to_jsonb(r) FROM rpc r),
    'constraints', (SELECT jsonb_agg(jsonb_build_object('name',c.conname,'valid',c.convalidated,
                         'definition',pg_get_constraintdef(c.oid)) ORDER BY c.conname)
                    FROM pg_constraint c WHERE c.conrelid IN (SELECT oid FROM targets)),
    'indexes', (SELECT jsonb_agg(jsonb_build_object('valid',i.indisvalid,
                     'definition',pg_get_indexdef(i.indexrelid)) ORDER BY i.indexrelid::regclass::text)
                FROM pg_index i WHERE i.indrelid IN (SELECT oid FROM targets))
) AS community_postflight;
