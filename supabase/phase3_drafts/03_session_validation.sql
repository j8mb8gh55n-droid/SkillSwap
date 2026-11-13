-- Review and rehearse in staging before applying.
BEGIN;

SET LOCAL lock_timeout = '5s';

CREATE FUNCTION public.validate_session_booking()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    IF NEW.scheduled_at <= clock_timestamp() THEN
        RAISE EXCEPTION 'Session time must be in the future' USING ERRCODE = '23514';
    END IF;
    IF NULLIF(btrim(NEW.location_or_link, E' \t\n\r'), '') IS NULL THEN
        RAISE EXCEPTION 'Session location or meeting link is required' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.validate_session_booking()
    FROM PUBLIC, anon, authenticated;

CREATE TRIGGER validate_session_booking_insert_t
    BEFORE INSERT ON public.sessions
    FOR EACH ROW EXECUTE FUNCTION public.validate_session_booking();

CREATE TRIGGER validate_session_booking_confirm_t
    BEFORE UPDATE OF status ON public.sessions
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'confirmed')
    EXECUTE FUNCTION public.validate_session_booking();

COMMIT;
