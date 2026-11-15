BEGIN;
CREATE TABLE public.chat_student_blocks (
    blocker_id uuid NOT NULL REFERENCES public.profiles(id),
    student_id uuid NOT NULL REFERENCES public.profiles(id),
    PRIMARY KEY (blocker_id, student_id),
    CHECK (blocker_id <> student_id)
);
ALTER TABLE public.chat_student_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_student_blocks FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.chat_student_blocks TO authenticated;
CREATE POLICY chat_blocks_own_read ON public.chat_student_blocks FOR SELECT TO authenticated
USING (blocker_id = (SELECT auth.uid()));

-- Preserve existing pair-level blocks whose original owner is unknown.
CREATE TABLE public.chat_legacy_blocks (conversation_id uuid PRIMARY KEY REFERENCES public.chat_conversations(id));
ALTER TABLE public.chat_legacy_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_legacy_blocks FROM PUBLIC, anon, authenticated;
LOCK TABLE public.chat_conversations IN SHARE ROW EXCLUSIVE MODE;
INSERT INTO public.chat_legacy_blocks SELECT id FROM public.chat_conversations WHERE status = 'blocked';

CREATE OR REPLACE FUNCTION public.chat_block(p_student uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor uuid := auth.uid();
BEGIN
    IF actor IS NULL OR p_student IS NULL OR actor = p_student THEN
        RAISE EXCEPTION 'Invalid messaging participants' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.chat_conversations (initiator_id, recipient_id, status)
    VALUES (actor, p_student, 'blocked')
    ON CONFLICT (least(initiator_id, recipient_id), greatest(initiator_id, recipient_id))
    DO UPDATE SET status = 'blocked';
    INSERT INTO public.chat_student_blocks VALUES (actor, p_student) ON CONFLICT DO NOTHING;
END;
$$;

CREATE FUNCTION public.chat_unblock(p_student uuid)
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
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.chat_unblock(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chat_unblock(uuid) TO authenticated;
COMMIT;
