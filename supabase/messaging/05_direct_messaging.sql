-- Direct messaging is independent of exchange approval.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE public.chat_conversations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    initiator_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'declined', 'blocked')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    latest_activity_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    initiator_read_through bigint NOT NULL DEFAULT 0 CHECK (initiator_read_through >= 0),
    recipient_read_through bigint NOT NULL DEFAULT 0 CHECK (recipient_read_through >= 0),
    CHECK (initiator_id <> recipient_id)
);

CREATE UNIQUE INDEX chat_conversations_pair_idx ON public.chat_conversations
    (least(initiator_id, recipient_id), greatest(initiator_id, recipient_id));
CREATE INDEX chat_conversations_initiator_activity_idx ON public.chat_conversations
    (initiator_id, latest_activity_at DESC);
CREATE INDEX chat_conversations_recipient_activity_idx ON public.chat_conversations
    (recipient_id, latest_activity_at DESC);

CREATE TABLE public.chat_messages (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES public.chat_conversations(id) ON DELETE RESTRICT,
    author_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
    body text NOT NULL CHECK (
        char_length(body) BETWEEN 1 AND 2000 AND body ~ '[^[:space:]]'
    ),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX chat_messages_thread_idx ON public.chat_messages (conversation_id, id DESC);

ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.chat_conversations, public.chat_messages FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, initiator_id, recipient_id, status, created_at, latest_activity_at)
    ON public.chat_conversations TO authenticated;
GRANT SELECT ON public.chat_messages TO authenticated;
REVOKE ALL ON SEQUENCE public.chat_messages_id_seq FROM PUBLIC, anon, authenticated;

CREATE POLICY chat_conversations_participant_read ON public.chat_conversations
    FOR SELECT TO authenticated
    USING ((SELECT auth.uid()) IN (initiator_id, recipient_id));

CREATE POLICY chat_messages_participant_read ON public.chat_messages
    FOR SELECT TO authenticated
    USING (EXISTS (
        SELECT 1 FROM public.chat_conversations c
        WHERE c.id = conversation_id AND (SELECT auth.uid()) IN (c.initiator_id, c.recipient_id)
    ));

CREATE FUNCTION public.chat_introduce(p_recipient uuid, p_body text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    actor uuid := auth.uid();
    thread_id uuid;
BEGIN
    IF actor IS NULL OR p_recipient IS NULL OR actor = p_recipient THEN
        RAISE EXCEPTION 'Invalid messaging participants' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.chat_conversations (initiator_id, recipient_id)
    VALUES (actor, p_recipient)
    ON CONFLICT (least(initiator_id, recipient_id), greatest(initiator_id, recipient_id))
    DO NOTHING RETURNING id INTO thread_id;

    IF FOUND THEN
        INSERT INTO public.chat_messages (conversation_id, author_id, body)
        VALUES (thread_id, actor, p_body);
        RETURN thread_id;
    END IF;

    SELECT c.id INTO thread_id FROM public.chat_conversations c
    WHERE least(c.initiator_id, c.recipient_id) = least(actor, p_recipient)
      AND greatest(c.initiator_id, c.recipient_id) = greatest(actor, p_recipient)
      AND c.status = 'accepted';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'An introduction is unavailable for this pair' USING ERRCODE = '55000';
    END IF;
    RETURN thread_id;
END;
$$;

CREATE FUNCTION public.chat_respond(p_conversation uuid, p_accept boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF p_accept IS NULL THEN
        RAISE EXCEPTION 'A response is required' USING ERRCODE = '22023';
    END IF;

    UPDATE public.chat_conversations
    SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END
    WHERE id = p_conversation AND recipient_id = auth.uid() AND status = 'pending';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No pending introduction can be answered' USING ERRCODE = '55000';
    END IF;
END;
$$;

CREATE FUNCTION public.chat_send(p_conversation uuid, p_body text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    actor uuid := auth.uid();
    message_id bigint;
    sent_at timestamptz;
BEGIN
    PERFORM 1 FROM public.chat_conversations
    WHERE id = p_conversation AND actor IN (initiator_id, recipient_id) AND status = 'accepted'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sending is unavailable for this conversation' USING ERRCODE = '55000';
    END IF;

    INSERT INTO public.chat_messages (conversation_id, author_id, body)
    VALUES (p_conversation, actor, p_body) RETURNING id, created_at INTO message_id, sent_at;
    UPDATE public.chat_conversations SET latest_activity_at = sent_at WHERE id = p_conversation;
    RETURN message_id;
END;
$$;

CREATE FUNCTION public.chat_block(p_student uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    actor uuid := auth.uid();
BEGIN
    IF actor IS NULL OR p_student IS NULL OR actor = p_student THEN
        RAISE EXCEPTION 'Invalid messaging participants' USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.chat_conversations AS c (initiator_id, recipient_id, status)
    VALUES (actor, p_student, 'blocked')
    ON CONFLICT (least(initiator_id, recipient_id), greatest(initiator_id, recipient_id))
    DO UPDATE SET status = 'blocked' WHERE c.status <> 'blocked';
END;
$$;

CREATE FUNCTION public.chat_mark_read(p_conversation uuid, p_message bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    actor uuid := auth.uid();
BEGIN
    UPDATE public.chat_conversations c
    SET initiator_read_through = CASE WHEN actor = c.initiator_id
            THEN greatest(c.initiator_read_through, p_message) ELSE c.initiator_read_through END,
        recipient_read_through = CASE WHEN actor = c.recipient_id
            THEN greatest(c.recipient_read_through, p_message) ELSE c.recipient_read_through END
    WHERE c.id = p_conversation AND actor IN (c.initiator_id, c.recipient_id)
      AND EXISTS (SELECT 1 FROM public.chat_messages m
                  WHERE m.conversation_id = c.id AND m.id = p_message);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Message cannot be marked read' USING ERRCODE = '55000';
    END IF;
END;
$$;

CREATE FUNCTION public.chat_unread_counts()
RETURNS TABLE (conversation_id uuid, unread_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
    SELECT c.id, count(m.id)
    FROM public.chat_conversations c
    LEFT JOIN public.chat_messages m ON m.conversation_id = c.id
        AND m.author_id <> auth.uid()
        AND m.id > CASE WHEN c.initiator_id = auth.uid()
                        THEN c.initiator_read_through ELSE c.recipient_read_through END
    WHERE auth.uid() IN (c.initiator_id, c.recipient_id)
      AND c.status IN ('pending', 'accepted')
    GROUP BY c.id;
$$;

REVOKE ALL ON FUNCTION public.chat_introduce(uuid,text), public.chat_respond(uuid,boolean),
    public.chat_send(uuid,text), public.chat_block(uuid), public.chat_mark_read(uuid,bigint), public.chat_unread_counts()
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chat_introduce(uuid,text), public.chat_respond(uuid,boolean),
    public.chat_send(uuid,text), public.chat_block(uuid), public.chat_mark_read(uuid,bigint), public.chat_unread_counts()
    TO authenticated;

COMMIT;
