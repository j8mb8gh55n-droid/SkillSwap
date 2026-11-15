-- Export this single metadata result from the SkillSwap SQL Editor.
WITH relations AS (
    SELECT c.oid, c.relname, c.relowner, c.relacl, c.relrowsecurity, c.relforcerowsecurity
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname IN ('profiles', 'student_skills', 'skills', 'exchanges', 'sessions',
                        'chat_conversations', 'chat_messages')
), columns AS (
    SELECT r.relname, a.attname, format_type(a.atttypid, a.atttypmod) AS data_type,
           a.attnotnull, a.attacl, pg_get_expr(d.adbin, d.adrelid) AS default_expression
    FROM relations r JOIN pg_attribute a ON a.attrelid = r.oid
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE a.attnum > 0 AND NOT a.attisdropped
), functions AS (
    SELECT p.oid::regprocedure::text AS signature,
           pg_get_userbyid(p.proowner) AS owner, p.prosecdef, p.proconfig, p.proacl,
           has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
           md5(pg_get_functiondef(p.oid)) AS definition_hash,
           CASE WHEN p.proname IN ('community_spotlight', 'discover_students')
                THEN pg_get_functiondef(p.oid) END AS definition
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prokind = 'f'
      AND ((n.nspname = 'auth' AND p.proname = 'uid')
        OR (n.nspname = 'public' AND
            (p.proname IN ('community_spotlight', 'discover_students', 'kudos_count', 'student_stats')
             OR p.proname ~ '^(chat_|exchange|session)'
             OR p.oid IN (SELECT t.tgfoid FROM pg_trigger t
                           WHERE t.tgrelid IN (SELECT oid FROM relations) AND NOT t.tgisinternal))))
), roles AS (
    SELECT caller.rolname AS caller, target.rolname AS role,
           caller.rolinherit AS caller_inherits, target.rolsuper, target.rolbypassrls,
           pg_has_role(caller.oid, target.oid, 'USAGE') AS privileges_available,
           pg_has_role(caller.oid, target.oid, 'SET') AS can_set_role,
           has_schema_privilege(caller.oid, 'public', 'CREATE') AS public_schema_create
    FROM pg_roles caller CROSS JOIN pg_roles target
    WHERE caller.rolname IN ('anon', 'authenticated')
      AND (caller.oid = target.oid OR pg_has_role(caller.oid, target.oid, 'MEMBER')
           OR pg_has_role(caller.oid, target.oid, 'SET'))
), privileges AS (
    SELECT r.relname, role_name,
           has_any_column_privilege(role_name, r.oid, 'SELECT') AS can_select,
           has_any_column_privilege(role_name, r.oid, 'UPDATE') AS can_update
    FROM relations r CROSS JOIN (VALUES ('anon'), ('authenticated')) AS clients(role_name)
)
SELECT jsonb_build_object(
    'server_version', current_setting('server_version'),
    'relations', (SELECT jsonb_agg(to_jsonb(r) - 'oid' - 'relowner' ||
                      jsonb_build_object('owner', pg_get_userbyid(r.relowner)) ORDER BY r.relname) FROM relations r),
    'columns', (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.relname, c.attname) FROM columns c),
    'constraints', (SELECT jsonb_agg(jsonb_build_object('table', r.relname, 'name', c.conname,
                       'validated', c.convalidated, 'definition', pg_get_constraintdef(c.oid))
                       ORDER BY r.relname, c.conname)
                    FROM relations r JOIN pg_constraint c ON c.conrelid = r.oid),
    'indexes', (SELECT jsonb_agg(jsonb_build_object('table', r.relname, 'valid', i.indisvalid,
                    'definition', pg_get_indexdef(i.indexrelid)) ORDER BY r.relname, i.indexrelid::regclass::text)
                FROM relations r JOIN pg_index i ON i.indrelid = r.oid),
    'policies', (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.tablename, p.policyname) FROM pg_policies p
                 WHERE p.schemaname = 'public' AND p.tablename IN (SELECT relname FROM relations)),
    'triggers', (SELECT jsonb_agg(jsonb_build_object('table', r.relname, 'enabled', t.tgenabled,
                     'definition', pg_get_triggerdef(t.oid)) ORDER BY r.relname, t.tgname)
                 FROM relations r JOIN pg_trigger t ON t.tgrelid = r.oid WHERE NOT t.tgisinternal),
    'effective_table_privileges', (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.relname, p.role_name) FROM privileges p),
    'roles', (SELECT jsonb_agg(to_jsonb(x) ORDER BY x.caller, x.role) FROM roles x),
    'functions', (SELECT jsonb_agg(to_jsonb(f) ORDER BY f.signature) FROM functions f)
) AS discoverability_preflight;
