-- ============================================================================
-- SkillSwap — Phase E1 migration: Kudos notification (additive)
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do NOT run until approved. RUN AFTER phase3_notifications.sql
-- (it reuses public.notify() and the public.notifications table/CHECK created
-- there). phase3 covers the 8 exchange/session events; this file adds the only
-- required event phase3 is missing: "Kudos received".
--
-- What it does (minimal, additive, idempotent):
--   1. Extends the notifications.type CHECK to allow 'kudos_received'.
--   2. Adds a dedup guard: at most one kudos notification per (exchange, recipient).
--   3. Adds an AFTER INSERT trigger on public.kudos that notifies the RECIPIENT
--      (actor = giver) via the existing SECURITY DEFINER public.notify() helper.
--
-- Security / privacy:
--   * Reuses public.notify() (SECURITY DEFINER, empty search_path, qualified
--     names) — clients still cannot INSERT notifications directly.
--   * The message is generic ("sent you kudos.") — it exposes NO kudos tags,
--     NO kudos message text, and no private content. Giver identity shown is the
--     same public profile (name/avatar) already visible app-wide.
--   * Does NOT modify the kudos table, its RLS, or its existing BEFORE-INSERT
--     validation trigger (kudos_validate_insert) — this only ADDS an AFTER trigger.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Allow the new event type (replace the CHECK with the full 9-type set).
--    phase3 created an unnamed column CHECK -> Postgres names it
--    'notifications_type_check'; drop-if-exists + re-add keeps this idempotent.
-- ----------------------------------------------------------------------------
alter table public.notifications
    drop constraint if exists notifications_type_check;

alter table public.notifications
    add constraint notifications_type_check
    check (type in (
        'request_received','request_accepted','request_declined',
        'session_proposed','session_confirmed','session_cancelled',
        'exchange_cancelled','completion_confirmed',
        'kudos_received'));

-- ----------------------------------------------------------------------------
-- 2. Dedup: one kudos notification per (exchange, recipient). One kudos per
--    giver per exchange already holds (kudos_one_per_giver), so this is the
--    natural once-only guard, consistent with phase3's completion dedup.
-- ----------------------------------------------------------------------------
create unique index if not exists notifications_kudos_received_uq
    on public.notifications (exchange_id, recipient_id)
    where type = 'kudos_received';

-- ----------------------------------------------------------------------------
-- 3. AFTER INSERT on kudos -> notify the recipient (actor = giver).
-- ----------------------------------------------------------------------------
create or replace function public.notifications_on_kudos_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.notify(
        new.recipient_id, new.giver_id, 'kudos_received',
        new.exchange_id, null, 'sent you kudos.');
    return new;
end;
$$;

revoke all on function public.notifications_on_kudos_insert() from public;

drop trigger if exists notifications_on_kudos_insert_t on public.kudos;
create trigger notifications_on_kudos_insert_t
    after insert on public.kudos
    for each row execute function public.notifications_on_kudos_insert();

-- ============================================================================
-- End of Phase E1 (kudos notification) migration.
-- ============================================================================
