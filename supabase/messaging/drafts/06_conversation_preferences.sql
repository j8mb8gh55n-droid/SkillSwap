BEGIN;
CREATE TABLE public.chat_conversation_preferences (
    conversation_id uuid NOT NULL REFERENCES public.chat_conversations(id),
    student_id uuid NOT NULL REFERENCES public.profiles(id),
    muted boolean NOT NULL DEFAULT false,
    hidden_through_message_id bigint,
    PRIMARY KEY (conversation_id, student_id)
);
ALTER TABLE public.chat_conversation_preferences ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_conversation_preferences FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.chat_conversation_preferences TO authenticated;
CREATE POLICY chat_preferences_own_read ON public.chat_conversation_preferences
FOR SELECT TO authenticated USING (student_id = (SELECT auth.uid()));

CREATE FUNCTION public.chat_set_muted(p_conversation uuid, p_muted boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.chat_conversations
        WHERE id = p_conversation AND auth.uid() IN (initiator_id, recipient_id)) THEN
        RAISE EXCEPTION 'Conversation unavailable' USING ERRCODE = '55000';
    END IF;
    INSERT INTO public.chat_conversation_preferences (conversation_id, student_id, muted)
    VALUES (p_conversation, auth.uid(), p_muted)
    ON CONFLICT (conversation_id, student_id) DO UPDATE SET muted = excluded.muted;
END;
$$;

CREATE FUNCTION public.chat_hide(p_conversation uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE cursor_id bigint;
BEGIN
    PERFORM 1 FROM public.chat_conversations WHERE id = p_conversation AND status = 'accepted'
        AND auth.uid() IN (initiator_id, recipient_id) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Conversation unavailable' USING ERRCODE = '55000'; END IF;
    SELECT coalesce(max(id), 0) INTO cursor_id FROM public.chat_messages WHERE conversation_id = p_conversation;
    INSERT INTO public.chat_conversation_preferences (conversation_id, student_id, hidden_through_message_id)
    VALUES (p_conversation, auth.uid(), cursor_id)
    ON CONFLICT (conversation_id, student_id) DO UPDATE SET hidden_through_message_id = excluded.hidden_through_message_id;
END;
$$;

CREATE VIEW public.chat_visible_inbox WITH (security_invoker = true) AS
SELECT c.id, c.initiator_id, c.recipient_id, c.status, c.created_at, c.latest_activity_at,
       coalesce(p.muted, false) AS muted
FROM public.chat_conversations c
LEFT JOIN public.chat_conversation_preferences p ON p.conversation_id = c.id AND p.student_id = (SELECT auth.uid())
WHERE p.hidden_through_message_id IS NULL OR EXISTS (
    SELECT 1 FROM public.chat_messages m WHERE m.conversation_id = c.id AND m.id > p.hidden_through_message_id
);
REVOKE ALL ON public.chat_visible_inbox FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.chat_visible_inbox TO authenticated;
REVOKE ALL ON FUNCTION public.chat_set_muted(uuid,boolean), public.chat_hide(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chat_set_muted(uuid,boolean), public.chat_hide(uuid) TO authenticated;
COMMIT;
