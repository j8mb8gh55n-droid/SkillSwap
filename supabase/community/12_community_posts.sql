BEGIN;

CREATE TABLE public.community_posts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    kind text NOT NULL CHECK (kind IN ('question', 'resource', 'project', 'tip')),
    title text NOT NULL CHECK (char_length(title) <= 120 AND title ~ '[^[:space:]]'),
    body text NOT NULL CHECK (char_length(body) <= 4000 AND body ~ '[^[:space:]]'),
    external_url text CHECK (external_url IS NULL OR (
        char_length(external_url) <= 2048 AND
        external_url ~ '^https://([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(:443)?([/?#][^[:space:][:cntrl:]\\]*)?$'
    )),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.community_post_skills (
    post_id uuid NOT NULL REFERENCES public.community_posts(id) ON DELETE CASCADE,
    skill_id bigint NOT NULL REFERENCES public.skills(id) ON DELETE RESTRICT,
    PRIMARY KEY (post_id, skill_id)
);

CREATE TABLE public.community_saved_posts (
    student_id uuid NOT NULL DEFAULT auth.uid() REFERENCES public.profiles(id) ON DELETE CASCADE,
    post_id uuid NOT NULL REFERENCES public.community_posts(id) ON DELETE CASCADE,
    PRIMARY KEY (student_id, post_id)
);

CREATE INDEX community_posts_latest_idx ON public.community_posts (created_at DESC, id DESC);
CREATE INDEX community_posts_author_idx ON public.community_posts (author_id, created_at DESC, id DESC);
CREATE INDEX community_post_skills_skill_idx ON public.community_post_skills (skill_id);
CREATE INDEX community_saved_posts_post_idx ON public.community_saved_posts (post_id);

ALTER TABLE public.community_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_post_skills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_saved_posts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.community_posts, public.community_post_skills, public.community_saved_posts
    FROM PUBLIC, anon, authenticated;
GRANT SELECT, DELETE ON public.community_posts TO authenticated;
GRANT SELECT ON public.community_post_skills TO authenticated;
GRANT SELECT, DELETE ON public.community_saved_posts TO authenticated;
GRANT INSERT (post_id) ON public.community_saved_posts TO authenticated;

CREATE POLICY community_posts_read ON public.community_posts
    FOR SELECT TO authenticated USING ((SELECT auth.uid()) IS NOT NULL);
CREATE POLICY community_posts_delete ON public.community_posts
    FOR DELETE TO authenticated USING (author_id = (SELECT auth.uid()));
CREATE POLICY community_post_skills_read ON public.community_post_skills
    FOR SELECT TO authenticated USING ((SELECT auth.uid()) IS NOT NULL);
CREATE POLICY community_saved_posts_read ON public.community_saved_posts
    FOR SELECT TO authenticated USING (student_id = (SELECT auth.uid()));
CREATE POLICY community_saved_posts_insert ON public.community_saved_posts
    FOR INSERT TO authenticated WITH CHECK (student_id = (SELECT auth.uid()));
CREATE POLICY community_saved_posts_delete ON public.community_saved_posts
    FOR DELETE TO authenticated USING (student_id = (SELECT auth.uid()));

CREATE FUNCTION public.community_save_post(
    p_kind text, p_title text, p_body text, p_skill_ids bigint[],
    p_external_url text DEFAULT NULL, p_post_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    caller uuid := auth.uid();
    target uuid;
BEGIN
    IF caller IS NULL THEN
        RAISE EXCEPTION 'Sign-in required' USING ERRCODE = '42501';
    END IF;
    IF COALESCE(cardinality(p_skill_ids), 0) NOT BETWEEN 1 AND 10
       OR (SELECT count(DISTINCT key) FROM unnest(p_skill_ids) AS skill(key)) <> cardinality(p_skill_ids) THEN
        RAISE EXCEPTION 'Choose one to ten distinct catalog skills' USING ERRCODE = '22023';
    END IF;

    IF p_post_id IS NULL THEN
        INSERT INTO public.community_posts (author_id, kind, title, body, external_url)
        VALUES (caller, p_kind, btrim(p_title), btrim(p_body), nullif(btrim(p_external_url), ''))
        RETURNING id INTO target;
    ELSE
        UPDATE public.community_posts
        SET kind = p_kind, title = btrim(p_title), body = btrim(p_body),
            external_url = nullif(btrim(p_external_url), ''), updated_at = clock_timestamp()
        WHERE id = p_post_id AND author_id = caller
        RETURNING id INTO target;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Post unavailable' USING ERRCODE = '42501';
        END IF;
        DELETE FROM public.community_post_skills WHERE post_id = target;
    END IF;

    INSERT INTO public.community_post_skills (post_id, skill_id)
    SELECT target, key FROM unnest(p_skill_ids) AS skill(key);
    RETURN target;
END;
$$;

REVOKE ALL ON FUNCTION public.community_save_post(text,text,text,bigint[],text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.community_save_post(text,text,text,bigint[],text,uuid) TO authenticated;

COMMIT;
