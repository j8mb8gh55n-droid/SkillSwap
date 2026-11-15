BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE SCHEMA chat_moderation_private;
REVOKE ALL ON SCHEMA chat_moderation_private FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE chat_moderation_private.members (
    user_id uuid PRIMARY KEY,
    granted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    revoked_at timestamptz
);

ALTER TABLE public.chat_reports
    ADD COLUMN status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'reviewed', 'resolved'));
CREATE INDEX chat_reports_queue_idx ON public.chat_reports (status, created_at DESC, id DESC);

CREATE TABLE chat_moderation_private.actions (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    report_id uuid NOT NULL REFERENCES public.chat_reports(id),
    moderator_id uuid NOT NULL,
    previous_status text NOT NULL CHECK (previous_status IN ('pending', 'reviewed')),
    new_status text NOT NULL CHECK (new_status IN ('reviewed', 'resolved')),
    acted_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX chat_moderation_actions_report_idx
    ON chat_moderation_private.actions (report_id, id);
ALTER TABLE chat_moderation_private.members ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_moderation_private.actions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA chat_moderation_private
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA chat_moderation_private
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.chat_reports FROM service_role;

CREATE FUNCTION chat_moderation_private.require_member()
RETURNS uuid LANGUAGE plpgsql SECURITY INVOKER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid();
BEGIN
    PERFORM 1 FROM chat_moderation_private.members
    WHERE user_id = actor AND revoked_at IS NULL FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Moderator access required' USING ERRCODE = '42501';
    END IF;
    RETURN actor;
END;
$$;
REVOKE ALL ON FUNCTION chat_moderation_private.require_member()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.chat_moderation_queue(
    p_status text DEFAULT 'pending', p_limit integer DEFAULT 25,
    p_before_time timestamptz DEFAULT NULL, p_before_id uuid DEFAULT NULL
)
RETURNS TABLE (report_id uuid, reason text, status text, created_at timestamptz,
               reported_name text, has_evidence boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := chat_moderation_private.require_member();
BEGIN
    IF p_status IS NULL OR p_status NOT IN ('pending', 'reviewed', 'resolved')
       OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50
       OR (p_before_time IS NULL) <> (p_before_id IS NULL) THEN
        RAISE EXCEPTION 'Invalid queue parameters' USING ERRCODE = '22023';
    END IF;
    RETURN QUERY
    SELECT r.id, r.reason, r.status, r.created_at, p.full_name, r.message_id IS NOT NULL
    FROM public.chat_reports r JOIN public.profiles p ON p.id = r.reported_id
    WHERE r.status = p_status AND actor NOT IN (r.reporter_id, r.reported_id)
      AND (p_before_time IS NULL OR (r.created_at, r.id) < (p_before_time, p_before_id))
    ORDER BY r.created_at DESC, r.id DESC LIMIT p_limit;
END;
$$;

CREATE FUNCTION public.chat_moderation_detail(p_report uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := chat_moderation_private.require_member(); result jsonb;
BEGIN
    SELECT jsonb_build_object(
        'report_id', r.id, 'reason', r.reason, 'status', r.status,
        'details', r.details, 'created_at', r.created_at,
        'reporter_name', reporter.full_name, 'reported_name', reported.full_name,
        'evidence', CASE WHEN m.id IS NOT NULL THEN
            jsonb_build_object('id', m.id, 'body', m.body, 'created_at', m.created_at) END,
        'actions', coalesce((SELECT jsonb_agg(jsonb_build_object(
            'moderator_id', a.moderator_id, 'previous_status', a.previous_status,
            'new_status', a.new_status, 'acted_at', a.acted_at) ORDER BY a.id)
            FROM chat_moderation_private.actions a WHERE a.report_id = r.id), '[]'::jsonb)
    ) INTO result
    FROM public.chat_reports r
    JOIN public.profiles reporter ON reporter.id = r.reporter_id
    JOIN public.profiles reported ON reported.id = r.reported_id
    LEFT JOIN public.chat_messages m ON m.id = r.message_id
        AND m.conversation_id = r.conversation_id AND m.author_id = r.reported_id
    WHERE r.id = p_report AND actor NOT IN (r.reporter_id, r.reported_id);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report unavailable' USING ERRCODE = '55000';
    END IF;
    RETURN result;
END;
$$;

CREATE FUNCTION public.chat_moderation_action(p_report uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := chat_moderation_private.require_member(); previous text;
BEGIN
    SELECT status INTO previous FROM public.chat_reports
    WHERE id = p_report AND actor NOT IN (reporter_id, reported_id) FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report unavailable' USING ERRCODE = '55000';
    END IF;
    IF p_status IS NULL OR NOT (
        (previous = 'pending' AND p_status IN ('reviewed', 'resolved'))
        OR (previous = 'reviewed' AND p_status = 'resolved')
    ) THEN
        RAISE EXCEPTION 'Invalid moderation transition' USING ERRCODE = '55000';
    END IF;
    UPDATE public.chat_reports SET status = p_status WHERE id = p_report;
    INSERT INTO chat_moderation_private.actions (report_id, moderator_id, previous_status, new_status)
    VALUES (p_report, actor, previous, p_status);
END;
$$;

REVOKE ALL ON FUNCTION public.chat_moderation_queue(text,integer,timestamptz,uuid),
    public.chat_moderation_detail(uuid), public.chat_moderation_action(uuid,text)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chat_moderation_queue(text,integer,timestamptz,uuid),
    public.chat_moderation_detail(uuid), public.chat_moderation_action(uuid,text)
    TO authenticated;
COMMIT;
