BEGIN;
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('chat-attachments', 'chat-attachments', false, 5242880, ARRAY['image/jpeg', 'image/png']);

CREATE TABLE public.chat_message_attachments (
    message_id bigint PRIMARY KEY REFERENCES public.chat_messages(id),
    object_name text NOT NULL UNIQUE,
    mime_type text NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png')),
    byte_count integer NOT NULL CHECK (byte_count BETWEEN 1 AND 5242880)
);
ALTER TABLE public.chat_message_attachments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_message_attachments FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.chat_message_attachments TO authenticated;
CREATE POLICY chat_attachment_participant_read ON public.chat_message_attachments
FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.chat_messages m WHERE m.id = message_id)
);
-- Requires a trusted upload endpoint and a Storage backend with service-role access.
CREATE FUNCTION public.chat_finalize_attachment(
    p_actor uuid, p_conversation uuid, p_object uuid, p_mime text, p_bytes integer
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE sent_id bigint; sent_at timestamptz; object_path text := p_conversation::text || '/' || p_object::text;
BEGIN
    PERFORM 1 FROM public.chat_conversations WHERE id = p_conversation
        AND p_actor IN (initiator_id, recipient_id) AND status = 'accepted' FOR UPDATE;
    IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM storage.objects
        WHERE bucket_id = 'chat-attachments' AND name = object_path
          AND metadata->>'mimetype' = p_mime AND metadata->>'size' = p_bytes::text) THEN
        RAISE EXCEPTION 'Attachment unavailable' USING ERRCODE = '55000';
    END IF;
    INSERT INTO public.chat_messages (conversation_id, author_id, body)
    VALUES (p_conversation, p_actor, 'Photo attachment') RETURNING id, created_at INTO sent_id, sent_at;
    INSERT INTO public.chat_message_attachments VALUES (sent_id, object_path, p_mime, p_bytes);
    UPDATE public.chat_conversations SET latest_activity_at = sent_at WHERE id = p_conversation;
    RETURN sent_id;
END;
$$;
REVOKE ALL ON FUNCTION public.chat_finalize_attachment(uuid,uuid,uuid,text,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chat_finalize_attachment(uuid,uuid,uuid,text,integer) TO service_role;
COMMIT;
