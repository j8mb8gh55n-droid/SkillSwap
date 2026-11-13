-- Apply after draft 03 on a verified copy of the deployed schema.
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.sessions
    ADD COLUMN replaces_session_id uuid REFERENCES public.sessions(id);

-- Historical rows remain intact. Existing conflicts abort the migration.
CREATE UNIQUE INDEX sessions_one_confirmed_per_exchange_idx
    ON public.sessions (exchange_id) WHERE status = 'confirmed';

CREATE FUNCTION public.coordinate_session_booking()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
    booked public.sessions%ROWTYPE;
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Scheduling requires read committed isolation';
    END IF;
    IF NOT pg_try_advisory_xact_lock(hashtextextended(NEW.exchange_id::text, 308)) THEN
        RAISE EXCEPTION 'Exchange is being updated. Try again.' USING ERRCODE = '40001';
    END IF;
    IF TG_OP = 'UPDATE'
       AND NEW.replaces_session_id IS DISTINCT FROM OLD.replaces_session_id THEN
        RAISE EXCEPTION 'A session replacement link is immutable';
    END IF;
    IF TG_OP = 'UPDATE' AND
       (NEW.status = OLD.status OR NEW.status <> 'confirmed') THEN
        RETURN NEW;
    END IF;

    -- Recheck after acquiring the lock against a concurrent exchange closure.
    IF NOT EXISTS (
        SELECT 1 FROM public.exchanges
        WHERE id = NEW.exchange_id AND status = 'accepted'
    ) THEN
        RAISE EXCEPTION 'Sessions require an accepted exchange';
    END IF;

    SELECT * INTO booked FROM public.sessions
    WHERE exchange_id = NEW.exchange_id AND status = 'confirmed';

    IF TG_OP = 'INSERT' THEN
        IF booked.id IS NOT NULL AND booked.scheduled_at <= clock_timestamp() THEN
            RAISE EXCEPTION 'The confirmed session has already taken place';
        END IF;
        NEW.replaces_session_id := booked.id;
        RETURN NEW;
    END IF;

    IF NEW.replaces_session_id IS DISTINCT FROM booked.id
       OR (booked.id IS NOT NULL AND booked.scheduled_at <= clock_timestamp()) THEN
        RAISE EXCEPTION 'The original booking changed. Propose a new time.';
    END IF;
    IF booked.id IS NOT NULL THEN
        -- Avoid waiting on a writer that already locked this session row.
        PERFORM 1 FROM public.sessions WHERE id = booked.id FOR UPDATE NOWAIT;
        UPDATE public.sessions SET status = 'cancelled' WHERE id = booked.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE FUNCTION public.close_exchange_sessions()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'Scheduling requires read committed isolation';
    END IF;
    IF NOT pg_try_advisory_xact_lock(hashtextextended(OLD.id::text, 308)) THEN
        RAISE EXCEPTION 'Exchange is being updated. Try again.' USING ERRCODE = '40001';
    END IF;
    IF OLD.status = 'accepted' AND NEW.status = 'cancelled' THEN
        -- The parent row is still accepted while the session guards run.
        PERFORM 1 FROM public.sessions
        WHERE exchange_id = OLD.id
          AND (status = 'proposed' OR (status = 'confirmed' AND scheduled_at > statement_timestamp()))
        FOR UPDATE NOWAIT;

        UPDATE public.sessions SET status = 'cancelled'
        WHERE exchange_id = OLD.id
          AND (status = 'proposed' OR (status = 'confirmed' AND scheduled_at > statement_timestamp()));
    END IF;
    RETURN NEW;
END;
$$;

-- Run after the existing authorization guards.
CREATE TRIGGER zz_coordinate_session_booking_t
    BEFORE INSERT OR UPDATE ON public.sessions
    FOR EACH ROW EXECUTE FUNCTION public.coordinate_session_booking();

CREATE TRIGGER zz_close_exchange_sessions_t
    BEFORE UPDATE ON public.exchanges
    FOR EACH ROW EXECUTE FUNCTION public.close_exchange_sessions();

REVOKE EXECUTE ON FUNCTION public.coordinate_session_booking(),
    public.close_exchange_sessions() FROM PUBLIC, anon, authenticated;

create or replace function public.notifications_on_session_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor       uuid := auth.uid();
    requester   uuid;
    recipient   uuid;
    proposer    uuid := old.proposed_by;
    other       uuid;
begin
    if new.status is distinct from old.status then
        select e.requester_id, e.recipient_id into requester, recipient
          from public.exchanges e where e.id = new.exchange_id;
        other := case when proposer = requester then recipient else requester end;

        if old.status = 'proposed' and new.status = 'confirmed' then
            perform public.notify(proposer, actor, 'session_confirmed',
                new.exchange_id, new.id,
                case when new.replaces_session_id is null
                     then 'confirmed your proposed session.'
                     else 'confirmed your rescheduled session.' end);
        elsif new.status = 'cancelled' and pg_trigger_depth() = 1 then
            -- The parent action sends the notice for nested cancellations.
            -- Notify whichever participant did NOT cancel.
            perform public.notify(
                case when actor = proposer then other else proposer end,
                actor, 'session_cancelled',
                new.exchange_id, new.id, 'cancelled a scheduled session.');
        end if;
    end if;
    return new;
end;
$$;

COMMIT;
