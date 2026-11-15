-- Run this and re-export preflight_read_only.sql for baseline comparison.
WITH preference AS (
    SELECT a.attnotnull, format_type(a.atttypid, a.atttypmod) AS type,
           pg_get_expr(d.adbin, d.adrelid) AS default_expression
    FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE a.attrelid = 'public.profiles'::regclass
      AND a.attname = 'discoverable_in_explore' AND NOT a.attisdropped
), discovery AS (
    SELECT NOT p.prosecdef AS security_invoker, p.proconfig, p.provolatile,
           pg_get_functiondef(p.oid) AS definition,
           has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
           has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
           EXISTS (SELECT 1 FROM aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
                   WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE') AS public_execute
    FROM pg_proc p WHERE p.oid = to_regprocedure('public.discover_students(uuid,integer)')
)
SELECT jsonb_build_object(
    'column', (SELECT to_jsonb(p) FROM preference p),
    'rpc', (SELECT to_jsonb(d) FROM discovery d),
    'profile_rls', (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.profiles'::regclass)
) AS discoverability_postflight;
