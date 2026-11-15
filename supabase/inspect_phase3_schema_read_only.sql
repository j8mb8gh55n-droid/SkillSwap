-- Catalog inventory for the Supabase SQL Editor. One result set for CSV export.
-- Routine bodies, column defaults, and migration SQL are omitted.
-- Quoted literals in catalog expressions are masked.

WITH expected(schema_name, table_name) AS (
    VALUES
        ('public', 'profiles'), ('public', 'skills'), ('public', 'student_skills'),
        ('public', 'availability'), ('public', 'exchanges'), ('public', 'sessions'),
        ('public', 'notifications'), ('public', 'kudos'),
        ('public', 'conversations'), ('public', 'messages'),
        ('public', 'reports'), ('public', 'moderation_actions'),
        ('public', 'posts'), ('public', 'comments'), ('public', 'reactions'),
        ('auth', 'users'), ('storage', 'objects'), ('storage', 'buckets')
), relations AS (
    SELECT e.*, c.oid, c.relkind, c.relrowsecurity, c.relforcerowsecurity
    FROM expected e
    LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = e.schema_name
    LEFT JOIN pg_catalog.pg_class c ON c.relnamespace = n.oid AND c.relname = e.table_name
), routines AS (
    SELECT p.*, n.nspname
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE p.prokind = 'f'
      AND (
        (n.nspname = 'public' AND p.proname IN (
            'handle_new_user', 'exchanges_validate_insert', 'exchanges_guard',
            'sessions_validate_insert', 'sessions_guard', 'notify',
            'notifications_guard', 'notifications_on_exchange_insert',
            'notifications_on_exchange_update', 'notifications_on_session_insert',
            'notifications_on_session_update', 'notifications_on_kudos_insert',
            'kudos_validate_insert', 'kudos_count', 'student_stats', 'community_spotlight'
        ))
        OR EXISTS (
            SELECT 1 FROM pg_catalog.pg_trigger t
            JOIN relations r ON r.oid = t.tgrelid
            WHERE t.tgfoid = p.oid AND NOT t.tgisinternal
        )
      )
), ledger AS (
    SELECT oid IS NOT NULL AS present,
           COALESCE(has_column_privilege(oid, 'version', 'SELECT'), false) AS version_readable
    FROM (SELECT pg_catalog.to_regclass('supabase_migrations.schema_migrations') AS oid) m
), inventory(section, object_name, details) AS (
    SELECT '01 public relation inventory', c.relname::text,
           jsonb_build_object('kind', c.relkind)
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm', 'f')

    UNION ALL
    SELECT '02 expected relations', schema_name || '.' || table_name,
           jsonb_build_object('present', oid IS NOT NULL, 'kind', relkind,
                              'rls_enabled', relrowsecurity, 'rls_forced', relforcerowsecurity)
    FROM relations

    UNION ALL
    SELECT '03 columns', r.schema_name || '.' || r.table_name || '.' || a.attname,
           jsonb_build_object('position', a.attnum,
                              'type', pg_catalog.format_type(a.atttypid, a.atttypmod),
                              'not_null', a.attnotnull, 'has_default', a.atthasdef)
    FROM relations r
    JOIN pg_catalog.pg_attribute a ON a.attrelid = r.oid
    WHERE a.attnum > 0 AND NOT a.attisdropped

    UNION ALL
    SELECT '04 RLS policies', p.schemaname || '.' || p.tablename || '.' || p.policyname,
           jsonb_build_object('mode', p.permissive, 'roles', p.roles, 'command', p.cmd,
             'using', regexp_replace(p.qual, '''(''''|[^''])*''', '<literal>', 'g'),
             'with_check', regexp_replace(p.with_check, '''(''''|[^''])*''', '<literal>', 'g'))
    FROM pg_catalog.pg_policies p
    JOIN relations r ON r.schema_name = p.schemaname AND r.table_name = p.tablename

    UNION ALL
    SELECT '05 effective client grants', r.schema_name || '.' || r.table_name || '.' || g.role_name,
           jsonb_build_object('table_select', has_table_privilege(g.role_name, r.oid, 'SELECT'),
             'schema_usage', has_schema_privilege(g.role_name, r.schema_name, 'USAGE'),
             'table_insert', has_table_privilege(g.role_name, r.oid, 'INSERT'),
             'table_update', has_table_privilege(g.role_name, r.oid, 'UPDATE'),
             'table_delete', has_table_privilege(g.role_name, r.oid, 'DELETE'),
             'select_columns', ARRAY(
                 SELECT a.attname FROM pg_catalog.pg_attribute a
                 WHERE a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped
                   AND has_column_privilege(g.role_name, r.oid, a.attnum, 'SELECT')
                 ORDER BY a.attnum
             ))
    FROM relations r
    CROSS JOIN (VALUES ('anon'), ('authenticated')) g(role_name)
    WHERE r.oid IS NOT NULL

    UNION ALL
    SELECT '06 constraints', r.schema_name || '.' || r.table_name || '.' || c.conname,
           jsonb_build_object('validated', c.convalidated, 'type', c.contype,
             'definition', regexp_replace(pg_catalog.pg_get_constraintdef(c.oid),
                                          '''(''''|[^''])*''', '<literal>', 'g'))
    FROM relations r
    JOIN pg_catalog.pg_constraint c ON c.conrelid = r.oid

    UNION ALL
    SELECT '07 indexes', r.schema_name || '.' || r.table_name || '.' || c.relname,
           jsonb_build_object('unique', i.indisunique, 'valid', i.indisvalid,
             'definition', regexp_replace(pg_catalog.pg_get_indexdef(i.indexrelid),
                                          '''(''''|[^''])*''', '<literal>', 'g'))
    FROM relations r
    JOIN pg_catalog.pg_index i ON i.indrelid = r.oid
    JOIN pg_catalog.pg_class c ON c.oid = i.indexrelid

    UNION ALL
    SELECT '08 triggers', r.schema_name || '.' || r.table_name || '.' || t.tgname,
           jsonb_build_object('enabled_mode', t.tgenabled, 'function', t.tgfoid::regprocedure::text,
             'definition', regexp_replace(pg_catalog.pg_get_triggerdef(t.oid),
                                          '''(''''|[^''])*''', '<literal>', 'g'))
    FROM relations r
    JOIN pg_catalog.pg_trigger t ON t.tgrelid = r.oid AND NOT t.tgisinternal

    UNION ALL
    SELECT '09 functions', p.nspname || '.' || p.proname || '(' ||
                          pg_catalog.oidvectortypes(p.proargtypes) || ')',
           jsonb_build_object('security_definer', p.prosecdef, 'volatility', p.provolatile,
             'search_path_is_set', EXISTS (
                 SELECT 1 FROM unnest(p.proconfig) AS config(setting)
                 WHERE config.setting LIKE 'search_path=%'
             ),
             'anon_execute', has_function_privilege('anon', p.oid, 'EXECUTE'),
             'authenticated_execute', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
             'definition_fingerprint', md5(pg_catalog.pg_get_functiondef(p.oid)))
    FROM routines p

    UNION ALL
    SELECT '10 migration ledger', 'supabase_migrations.schema_migrations',
           jsonb_build_object('present', present, 'version_readable', version_readable)
    FROM ledger

    UNION ALL
    SELECT '11 recorded migration versions', m.version, '{}'::jsonb
    FROM ledger
    CROSS JOIN LATERAL XMLTABLE(
        '/table/row' PASSING
        CASE WHEN version_readable THEN pg_catalog.query_to_xml(
            'SELECT version FROM supabase_migrations.schema_migrations', false, false, ''
        ) ELSE XMLPARSE(DOCUMENT '<table/>') END
        COLUMNS version text PATH 'version'
    ) m
)
SELECT section, object_name, details
FROM inventory
ORDER BY section, object_name;
