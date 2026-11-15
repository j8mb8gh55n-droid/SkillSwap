-- Export the single result. This query returns schema metadata only.
WITH relations AS (
    SELECT c.oid, c.relname, c.relkind, pg_get_userbyid(c.relowner) AS owner,
           c.relrowsecurity, c.relforcerowsecurity, c.relacl
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND (c.relname IN ('profiles', 'skills', 'student_skills', 'exchanges', 'sessions',
                        'chat_conversations', 'chat_messages')
           OR c.relname LIKE 'community_%')
), roles AS (
    SELECT c.rolname AS caller, t.rolname AS role, t.rolsuper, t.rolbypassrls,
           pg_has_role(c.oid,t.oid,'USAGE') AS effective,
           pg_has_role(c.oid,t.oid,'SET') AS can_set,
           has_schema_privilege(c.oid, 'public', 'CREATE') AS can_create_public
    FROM pg_roles c CROSS JOIN pg_roles t
    WHERE c.rolname IN ('anon','authenticated')
      AND (c.oid=t.oid OR pg_has_role(c.oid,t.oid,'MEMBER'))
), functions AS (
    SELECT p.oid::regprocedure::text AS signature, pg_get_userbyid(p.proowner) AS owner,
           p.prosecdef, p.proconfig, p.proacl, md5(pg_get_functiondef(p.oid)) AS definition_hash,
           has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,
           has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE p.prokind='f'
      AND ((n.nspname='auth' AND p.proname='uid')
        OR (n.nspname='public' AND (p.proname ~ '^(chat_|community_|discover_students$)'
           OR p.oid IN (SELECT tgfoid FROM pg_trigger
                         WHERE tgrelid IN (SELECT oid FROM relations) AND NOT tgisinternal))))
)
SELECT jsonb_build_object(
    'version', current_setting('server_version'),
    'operator', current_user,
    'can_create_public', has_schema_privilege(current_user,'public','CREATE'),
    'relations', (SELECT jsonb_agg(to_jsonb(r)-'oid' ORDER BY r.relname) FROM relations r),
    'columns', (SELECT jsonb_agg(jsonb_build_object('relation',r.relname,'name',a.attname,
                          'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,
                          'default',pg_get_expr(d.adbin,d.adrelid),'acl',a.attacl) ORDER BY r.relname,a.attnum)
                FROM relations r JOIN pg_attribute a ON a.attrelid=r.oid
                LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
                WHERE a.attnum>0 AND NOT a.attisdropped AND r.relkind IN ('r','p','v')),
    'policies', (SELECT jsonb_agg(to_jsonb(p) ORDER BY tablename,policyname) FROM pg_policies p
                 WHERE schemaname='public' AND tablename IN (SELECT relname FROM relations)),
    'constraints', (SELECT jsonb_agg(jsonb_build_object('table',c.conrelid::regclass::text,
                        'name',c.conname,'valid',c.convalidated,'definition',pg_get_constraintdef(c.oid))
                          ORDER BY c.conrelid::regclass::text,c.conname)
                    FROM pg_constraint c
                    WHERE c.conrelid IN (SELECT oid FROM relations) OR c.confrelid IN
                          (SELECT oid FROM relations WHERE relname IN ('profiles','skills'))),
    'functions', (SELECT jsonb_agg(to_jsonb(f) ORDER BY signature) FROM functions f),
    'roles', (SELECT jsonb_agg(to_jsonb(r) ORDER BY caller,role) FROM roles r),
    'type_conflicts', (SELECT jsonb_agg(t.typname ORDER BY t.typname)
                       FROM pg_type t JOIN pg_namespace n ON n.oid=t.typnamespace
                       WHERE n.nspname='public' AND t.typname IN
                             ('community_posts','community_post_skills','community_saved_posts')),
    'default_acl', (SELECT jsonb_agg(jsonb_build_object('owner',pg_get_userbyid(d.defaclrole),
                            'schema',n.nspname,'object',d.defaclobjtype,'acl',d.defaclacl)
                              ORDER BY d.defaclrole,d.defaclnamespace,d.defaclobjtype)
                    FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid=d.defaclnamespace
                    WHERE d.defaclnamespace=0 OR n.nspname='public')
) AS community_preflight;
