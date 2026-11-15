BEGIN;

ALTER TABLE public.profiles
    ADD COLUMN discoverable_in_explore boolean NOT NULL DEFAULT true;

CREATE FUNCTION public.discover_students(p_after uuid DEFAULT NULL, p_limit integer DEFAULT 100)
RETURNS TABLE (
    id uuid,
    full_name text,
    major text,
    bio text,
    avatar_url text,
    availability_status text,
    skill_links jsonb
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
    WITH caller AS (SELECT auth.uid() AS id),
    eligible AS MATERIALIZED (
        SELECT p.id, p.full_name, p.major, p.bio, p.avatar_url, p.availability_status
        FROM public.profiles p CROSS JOIN caller
        WHERE caller.id IS NOT NULL
          AND p.id <> caller.id
          AND p.discoverable_in_explore
          AND pg_catalog.btrim(COALESCE(p.full_name, '')) <> ''
          AND (p_after IS NULL OR p.id > p_after)
        ORDER BY p.id
        LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 200)
    )
    SELECT e.id, e.full_name, e.major, e.bio, e.avatar_url, e.availability_status,
           COALESCE(links.skill_links, '[]'::jsonb)
    FROM eligible e
    LEFT JOIN LATERAL (
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
            'skill_type', l.skill_type,
            'experience_level', l.experience_level,
            'skills', pg_catalog.jsonb_build_object('id', s.id, 'name', s.name, 'category', s.category)
        ) ORDER BY l.id) AS skill_links
        FROM public.student_skills l
        JOIN public.skills s ON s.id = l.skill_id
        WHERE l.student_id = e.id
    ) links ON true
    ORDER BY e.id;
$$;

REVOKE ALL ON FUNCTION public.discover_students(uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.discover_students(uuid, integer) TO authenticated;

COMMIT;
