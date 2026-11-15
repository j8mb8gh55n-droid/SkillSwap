BEGIN;
CREATE TABLE public.chat_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id uuid NOT NULL REFERENCES public.profiles(id),
    conversation_id uuid NOT NULL REFERENCES public.chat_conversations(id),
    reported_id uuid NOT NULL REFERENCES public.profiles(id),
    message_id bigint REFERENCES public.chat_messages(id),
    reason text NOT NULL CHECK (reason IN ('harassment', 'spam', 'inappropriate_content', 'safety_concern', 'other')),
    details text CHECK (char_length(details) <= 500),
    UNIQUE NULLS NOT DISTINCT (reporter_id, conversation_id, message_id),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX chat_reports_reporter_created_idx ON public.chat_reports (reporter_id, created_at DESC);
ALTER TABLE public.chat_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_reports FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.chat_report(p_conversation uuid, p_reason text, p_message bigint DEFAULT NULL, p_details text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); student uuid; report_id uuid;
BEGIN
    SELECT CASE WHEN initiator_id = actor THEN recipient_id ELSE initiator_id END INTO student
    FROM public.chat_conversations WHERE id = p_conversation AND actor IN (initiator_id, recipient_id);
    IF NOT FOUND OR (p_message IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.chat_messages
        WHERE id = p_message AND conversation_id = p_conversation AND author_id = student)) THEN
        RAISE EXCEPTION 'Report context unavailable' USING ERRCODE = '55000';
    END IF;
    -- Serialize submissions by the same authenticated reporter.
    PERFORM 1 FROM public.profiles WHERE id = actor FOR NO KEY UPDATE;
    IF EXISTS (SELECT 1 FROM public.chat_reports WHERE reporter_id = actor
        AND conversation_id = p_conversation AND message_id IS NOT DISTINCT FROM p_message) THEN
        RAISE EXCEPTION 'Report already submitted' USING ERRCODE = '23505';
    END IF;
    IF (SELECT count(*) FROM public.chat_reports WHERE reporter_id = actor
        AND created_at >= clock_timestamp() - interval '24 hours') >= 5 THEN
        RAISE EXCEPTION 'Report limit reached' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO public.chat_reports (reporter_id, conversation_id, reported_id, message_id, reason, details)
    VALUES (actor, p_conversation, student, p_message, p_reason, nullif(btrim(p_details), ''))
    RETURNING id INTO report_id;
    RETURN report_id;
END;
$$;
REVOKE ALL ON FUNCTION public.chat_report(uuid,text,bigint,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chat_report(uuid,text,bigint,text) TO authenticated;
COMMIT;
