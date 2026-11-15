BEGIN;
SET LOCAL lock_timeout = '5s';
CREATE TABLE public.chat_reconnections(
 conversation_id uuid PRIMARY KEY REFERENCES public.chat_conversations(id),
 requester_id uuid NOT NULL REFERENCES public.profiles(id),
 message_id bigint UNIQUE REFERENCES public.chat_messages(id)
);
ALTER TABLE public.chat_reconnections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_reconnections FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.chat_unblock(p_student uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid(); thread uuid;
BEGIN
    SELECT id INTO thread FROM public.chat_conversations
    WHERE least(initiator_id, recipient_id) = least(actor, p_student)
      AND greatest(initiator_id, recipient_id) = greatest(actor, p_student)
      AND actor IN (initiator_id, recipient_id) FOR UPDATE;
    DELETE FROM public.chat_student_blocks WHERE blocker_id = actor AND student_id = p_student;
    IF FOUND AND NOT EXISTS (SELECT 1 FROM public.chat_legacy_blocks WHERE conversation_id = thread)
      AND NOT EXISTS (SELECT 1 FROM public.chat_student_blocks WHERE blocker_id = p_student AND student_id = actor) THEN
        UPDATE public.chat_conversations SET status = 'declined' WHERE id = thread AND status = 'blocked';
        IF FOUND THEN
            INSERT INTO public.chat_reconnections AS r(conversation_id, requester_id)
            VALUES (thread, actor) ON CONFLICT (conversation_id)
            DO UPDATE SET requester_id = excluded.requester_id WHERE r.message_id IS NULL;
        END IF;
    END IF;
END;
$$;
CREATE OR REPLACE FUNCTION public.chat_respond(p_conversation uuid, p_accept boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF p_accept IS NULL THEN
        RAISE EXCEPTION 'A response is required' USING ERRCODE = '22023';
    END IF;

    PERFORM 1 FROM public.chat_conversations
    WHERE id = p_conversation AND auth.uid() = recipient_id FOR UPDATE;

    UPDATE public.chat_conversations c
    SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END
    WHERE id = p_conversation AND status = 'pending' AND auth.uid() = recipient_id
      AND NOT EXISTS (
          SELECT 1 FROM public.chat_reconnections r
          WHERE r.conversation_id = c.id AND r.message_id IS NOT NULL
      );
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No pending introduction can be answered' USING ERRCODE = '55000';
    END IF;
END;
$$;


CREATE FUNCTION public.chat_reconnect(p_conversation uuid,p_body text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=auth.uid(); sent_id bigint; sent_at timestamptz;
BEGIN
 PERFORM 1 FROM public.chat_conversations WHERE id=p_conversation
   AND actor IN (initiator_id,recipient_id) FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS (SELECT FROM public.chat_conversations WHERE id=p_conversation AND status='declined')
   OR NOT EXISTS (SELECT FROM public.chat_reconnections WHERE conversation_id=p_conversation
   AND requester_id=actor AND message_id IS NULL)
   OR EXISTS (SELECT FROM public.chat_legacy_blocks WHERE conversation_id=p_conversation)
   OR EXISTS (SELECT FROM public.chat_student_blocks b JOIN public.chat_conversations c
      ON c.id=p_conversation WHERE least(b.blocker_id,b.student_id)=least(c.initiator_id,c.recipient_id)
      AND greatest(b.blocker_id,b.student_id)=greatest(c.initiator_id,c.recipient_id)) THEN
    RAISE EXCEPTION 'Reconnection unavailable' USING ERRCODE='55000';
 END IF;
 INSERT INTO public.chat_messages(conversation_id,author_id,body)
 VALUES(p_conversation,actor,p_body) RETURNING id,created_at INTO sent_id,sent_at;
 UPDATE public.chat_reconnections SET message_id=sent_id WHERE conversation_id=p_conversation;
 UPDATE public.chat_conversations SET status='pending',latest_activity_at=sent_at WHERE id=p_conversation;
 RETURN sent_id;
END;
$$;
REVOKE ALL ON FUNCTION public.chat_reconnect(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.chat_reconnect(uuid,text) TO authenticated;

CREATE FUNCTION public.chat_respond_to_reconnection(p_conversation uuid, p_message bigint, p_accept boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
    IF p_accept IS NULL THEN
        RAISE EXCEPTION 'A response is required' USING ERRCODE = '22023';
    END IF;
    PERFORM 1 FROM public.chat_conversations
    WHERE id = p_conversation AND auth.uid() IN (initiator_id, recipient_id) FOR UPDATE;

    UPDATE public.chat_conversations c
    SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END
    FROM public.chat_reconnections r
    WHERE c.id = p_conversation AND c.status = 'pending'
      AND r.conversation_id = c.id AND r.message_id = p_message
      AND auth.uid() IN (c.initiator_id, c.recipient_id) AND auth.uid() <> r.requester_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No pending reconnection can be answered' USING ERRCODE = '55000';
    END IF;
END;
$$;

CREATE FUNCTION public.chat_threads(p_scope text, p_offset integer DEFAULT 0,
    p_limit integer DEFAULT 40, p_student uuid DEFAULT NULL)
RETURNS SETOF jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
    actor uuid := auth.uid();
    visibility_filter text := '';
BEGIN
    IF actor IS NULL THEN RETURN; END IF;
    IF p_scope IS NULL OR p_scope NOT IN ('inbox', 'received', 'sent', 'thread')
       OR p_offset IS NULL OR p_offset < 0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
       OR (p_scope = 'thread' AND p_student IS NULL) THEN
        RAISE EXCEPTION 'Invalid conversation query' USING ERRCODE = '22023';
    END IF;

    -- Apply private hide cursors if conversation preferences have been installed.
    IF p_scope = 'inbox' AND to_regclass('public.chat_conversation_preferences') IS NOT NULL THEN
        visibility_filter := ' AND NOT EXISTS (
            SELECT 1 FROM public.chat_conversation_preferences pref
            WHERE pref.conversation_id = c.id AND pref.student_id = $1
              AND pref.hidden_through_message_id IS NOT NULL
              AND coalesce(m.id, 0) <= pref.hidden_through_message_id
        )';
    END IF;
    RETURN QUERY EXECUTE '
        SELECT jsonb_build_object(
            ''id'', c.id, ''initiator_id'', c.initiator_id, ''recipient_id'', c.recipient_id,
            ''status'', c.status, ''latest_activity_at'', c.latest_activity_at,
            ''initiator'', jsonb_build_object(''full_name'', i.full_name, ''avatar_url'', i.avatar_url),
            ''recipient'', jsonb_build_object(''full_name'', t.full_name, ''avatar_url'', t.avatar_url),
            ''latest'', CASE WHEN m.id IS NULL THEN ''[]''::jsonb ELSE jsonb_build_array(to_jsonb(m)) END,
            ''can_reconnect'', coalesce(c.status = ''declined'' AND r.requester_id = $1 AND r.message_id IS NULL, false),
            ''reconnection_requester'', CASE WHEN c.status = ''pending'' AND r.message_id IS NOT NULL THEN r.requester_id END,
            ''reconnection_message'', CASE WHEN c.status = ''pending'' THEN r.message_id END
        )
        FROM public.chat_conversations c
        JOIN public.profiles i ON i.id = c.initiator_id
        JOIN public.profiles t ON t.id = c.recipient_id
        LEFT JOIN public.chat_reconnections r ON r.conversation_id = c.id
        LEFT JOIN LATERAL (
            SELECT id, author_id, body, created_at FROM public.chat_messages
            WHERE conversation_id = c.id ORDER BY id DESC LIMIT 1
        ) m ON true
        WHERE $1 IN (c.initiator_id, c.recipient_id)
          AND CASE $2
              WHEN ''thread'' THEN $3 IN (c.initiator_id, c.recipient_id) AND $3 <> $1
              WHEN ''received'' THEN c.status = ''pending'' AND coalesce(r.requester_id, c.initiator_id) <> $1
              WHEN ''sent'' THEN c.status = ''pending'' AND coalesce(r.requester_id, c.initiator_id) = $1
              ELSE c.status IN (''accepted'', ''pending'') OR m.id IS NOT NULL OR r.conversation_id IS NOT NULL
          END' || visibility_filter || '
        ORDER BY c.latest_activity_at DESC, c.id DESC OFFSET $4 LIMIT $5'
    USING actor, p_scope, p_student, p_offset, p_limit;
END;
$$;
REVOKE ALL ON FUNCTION public.chat_respond_to_reconnection(uuid,bigint,boolean),
    public.chat_threads(text,integer,integer,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chat_respond_to_reconnection(uuid,bigint,boolean),
    public.chat_threads(text,integer,integer,uuid) TO authenticated;
COMMIT;
