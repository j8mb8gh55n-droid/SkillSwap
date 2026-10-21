-- ============================================================================
-- SkillSwap — Phase 3 migration: in-app notifications
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do not run until approved.
--
-- Adds ONE new table (public.notifications) plus its security and the
-- database-side triggers that create notifications when exchange/session
-- events occur. Does NOT modify the existing tables' columns; it only ADDS
-- AFTER-triggers to public.exchanges and public.sessions (the existing
-- BEFORE guards in phase2_exchanges.sql are untouched and still run first).
--
-- Depends on: phase2_exchanges.sql (exchanges, sessions) and public.profiles.
-- Safe to run once; uses IF NOT EXISTS / CREATE OR REPLACE / DROP ... IF EXISTS.
--
-- Design goals (map to the approved requirements):
--   * In-app only — no APNs, no external delivery.
--   * Recipient-scoped RLS: a user may read ONLY their own notifications.
--   * No client forging: INSERT is NOT granted to authenticated/anon. Rows are
--     created exclusively by SECURITY DEFINER triggers below, so a client can
--     never fabricate a notification for an arbitrary recipient.
--   * Never notify a user about their OWN action: every trigger derives the
--     actor from auth.uid() and notifies the OTHER participant.
--   * No duplicate notifications per event: each notification is tied to the
--     specific state transition that produced it; partial unique indexes guard
--     the once-only events.
--   * Dismiss/read: the recipient may mark their own notifications read and may
--     delete their own (swipe-to-dismiss). They may not alter content.
--
-- Event types (8), matching the brief:
--   request_received      new incoming exchange request
--   request_accepted      your request was accepted
--   request_declined      your request was declined
--   session_proposed      the other participant proposed a session
--   session_confirmed     your proposed session was confirmed
--   session_cancelled     a session was cancelled by the other participant
--   exchange_cancelled    the exchange was cancelled by the other participant
--   completion_confirmed  the other participant confirmed completion
-- ============================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid()

-- ----------------------------------------------------------------------------
-- 1. notifications table
-- ----------------------------------------------------------------------------
create table if not exists public.notifications (
    id            uuid        primary key default gen_random_uuid(),
    recipient_id  uuid        not null references public.profiles(id) on delete cascade,
    actor_id      uuid                 references public.profiles(id) on delete set null,
    type          text        not null
                  check (type in (
                      'request_received','request_accepted','request_declined',
                      'session_proposed','session_confirmed','session_cancelled',
                      'exchange_cancelled','completion_confirmed')),
    exchange_id   uuid                 references public.exchanges(id) on delete cascade,
    session_id    uuid                 references public.sessions(id)  on delete cascade,
    message       text        not null,
    is_read       boolean     not null default false,
    created_at    timestamptz not null default now(),
    -- A notification is never about the recipient's own action.
    constraint notifications_actor_not_recipient check (actor_id is distinct from recipient_id)
);

create index if not exists notifications_recipient_idx
    on public.notifications (recipient_id, is_read, created_at desc);

-- Dedup guards for the once-only events: at most one of each per exchange.
create unique index if not exists notifications_request_received_uq
    on public.notifications (exchange_id) where type = 'request_received';
create unique index if not exists notifications_request_accepted_uq
    on public.notifications (exchange_id) where type = 'request_accepted';
create unique index if not exists notifications_request_declined_uq
    on public.notifications (exchange_id) where type = 'request_declined';
create unique index if not exists notifications_exchange_cancelled_uq
    on public.notifications (exchange_id) where type = 'exchange_cancelled';
-- Completion is confirmed independently by each side, so dedup per (exchange, recipient).
create unique index if not exists notifications_completion_uq
    on public.notifications (exchange_id, recipient_id) where type = 'completion_confirmed';
-- Session proposed/confirmed happen once per session; cancelled once per session.
create unique index if not exists notifications_session_proposed_uq
    on public.notifications (session_id) where type = 'session_proposed';
create unique index if not exists notifications_session_confirmed_uq
    on public.notifications (session_id) where type = 'session_confirmed';
create unique index if not exists notifications_session_cancelled_uq
    on public.notifications (session_id) where type = 'session_cancelled';

-- ----------------------------------------------------------------------------
-- 2. Row Level Security
-- ----------------------------------------------------------------------------
alter table public.notifications enable row level security;

-- Clients may read, mark-read, and dismiss their OWN notifications only.
-- INSERT is intentionally NOT granted: rows come only from the triggers below.
grant select, update, delete on public.notifications to authenticated;
revoke insert on public.notifications from authenticated, anon;

drop policy if exists notifications_select on public.notifications;
create policy notifications_select
    on public.notifications for select to authenticated
    using ( auth.uid() = recipient_id );

-- Update limited to the recipient; content immutability enforced by the guard
-- trigger below (only is_read may change, false -> true).
drop policy if exists notifications_update on public.notifications;
create policy notifications_update
    on public.notifications for update to authenticated
    using ( auth.uid() = recipient_id )
    with check ( auth.uid() = recipient_id );

drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete
    on public.notifications for delete to authenticated
    using ( auth.uid() = recipient_id );

-- ----------------------------------------------------------------------------
-- 3. Guard: recipients may only flip is_read (no editing content)
-- ----------------------------------------------------------------------------
create or replace function public.notifications_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if new.id          is distinct from old.id
       or new.recipient_id is distinct from old.recipient_id
       or new.actor_id     is distinct from old.actor_id
       or new.type         is distinct from old.type
       or new.exchange_id  is distinct from old.exchange_id
       or new.session_id   is distinct from old.session_id
       or new.message      is distinct from old.message
       or new.created_at   is distinct from old.created_at then
        raise exception 'Only the read state of a notification can be changed';
    end if;
    return new;
end;
$$;

revoke all on function public.notifications_guard() from public;

drop trigger if exists notifications_guard_t on public.notifications;
create trigger notifications_guard_t
    before update on public.notifications
    for each row execute function public.notifications_guard();

-- ----------------------------------------------------------------------------
-- 4. Creation helper (SECURITY DEFINER) — the ONLY way rows are inserted.
--    Definer rights bypass the (absent) INSERT grant and RLS, so triggers can
--    create a notification for the other participant without the client being
--    able to do so directly. Empty search_path + qualified names.
-- ----------------------------------------------------------------------------
create or replace function public.notify(
    p_recipient uuid,
    p_actor     uuid,
    p_type      text,
    p_exchange  uuid,
    p_session   uuid,
    p_message   text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    -- Never notify an actor about their own action, and never self-notify.
    if p_recipient is null or p_recipient = p_actor then
        return;
    end if;
    -- ON CONFLICT DO NOTHING makes the partial-unique dedup guards authoritative
    -- even under races / retries.
    insert into public.notifications
        (recipient_id, actor_id, type, exchange_id, session_id, message)
    values
        (p_recipient, p_actor, p_type, p_exchange, p_session, p_message)
    on conflict do nothing;
end;
$$;

revoke all on function public.notify(uuid,uuid,text,uuid,uuid,text) from public;

-- ----------------------------------------------------------------------------
-- 5. Exchange events
-- ----------------------------------------------------------------------------

-- 5a. New request -> notify the recipient. (actor = requester = auth.uid())
create or replace function public.notifications_on_exchange_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    perform public.notify(
        new.recipient_id, new.requester_id, 'request_received',
        new.id, null, 'sent you a new skill-exchange request.');
    return new;
end;
$$;

revoke all on function public.notifications_on_exchange_insert() from public;

drop trigger if exists notifications_on_exchange_insert_t on public.exchanges;
create trigger notifications_on_exchange_insert_t
    after insert on public.exchanges
    for each row execute function public.notifications_on_exchange_insert();

-- 5b. Exchange updates -> accepted / declined / cancelled / completion-by-other.
create or replace function public.notifications_on_exchange_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor uuid := auth.uid();
begin
    -- Status transitions.
    if new.status is distinct from old.status then
        if old.status = 'pending' and new.status = 'accepted' then
            perform public.notify(new.requester_id, actor, 'request_accepted',
                new.id, null, 'accepted your exchange request.');
        elsif old.status = 'pending' and new.status = 'declined' then
            perform public.notify(new.requester_id, actor, 'request_declined',
                new.id, null, 'declined your exchange request.');
        elsif new.status = 'cancelled' then
            -- Notify whichever participant did NOT perform the cancellation.
            perform public.notify(
                case when actor = new.requester_id then new.recipient_id else new.requester_id end,
                actor, 'exchange_cancelled',
                new.id, null, 'cancelled the exchange.');
        end if;
    end if;

    -- Completion confirmations: notify the OTHER participant when one side
    -- newly confirms. (The mutual-completion rules stay enforced by the
    -- phase-2 BEFORE guard; this only announces the event.)
    if new.requester_completed and not old.requester_completed then
        perform public.notify(new.recipient_id, new.requester_id, 'completion_confirmed',
            new.id, null, 'confirmed completion of your exchange.');
    end if;
    if new.recipient_completed and not old.recipient_completed then
        perform public.notify(new.requester_id, new.recipient_id, 'completion_confirmed',
            new.id, null, 'confirmed completion of your exchange.');
    end if;

    return new;
end;
$$;

revoke all on function public.notifications_on_exchange_update() from public;

drop trigger if exists notifications_on_exchange_update_t on public.exchanges;
create trigger notifications_on_exchange_update_t
    after update on public.exchanges
    for each row execute function public.notifications_on_exchange_update();

-- ----------------------------------------------------------------------------
-- 6. Session events
-- ----------------------------------------------------------------------------

-- 6a. Session proposed -> notify the other participant. (actor = proposed_by)
create or replace function public.notifications_on_session_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    other uuid;
begin
    select case when new.proposed_by = e.requester_id then e.recipient_id
                else e.requester_id end
      into other
      from public.exchanges e
     where e.id = new.exchange_id;

    perform public.notify(other, new.proposed_by, 'session_proposed',
        new.exchange_id, new.id, 'proposed a session time.');
    return new;
end;
$$;

revoke all on function public.notifications_on_session_insert() from public;

drop trigger if exists notifications_on_session_insert_t on public.sessions;
create trigger notifications_on_session_insert_t
    after insert on public.sessions
    for each row execute function public.notifications_on_session_insert();

-- 6b. Session confirmed / cancelled.
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
            -- The OTHER participant confirmed; tell the proposer.
            perform public.notify(proposer, actor, 'session_confirmed',
                new.exchange_id, new.id, 'confirmed your proposed session.');
        elsif new.status = 'cancelled' then
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

revoke all on function public.notifications_on_session_update() from public;

drop trigger if exists notifications_on_session_update_t on public.sessions;
create trigger notifications_on_session_update_t
    after update on public.sessions
    for each row execute function public.notifications_on_session_update();

-- ============================================================================
-- NOTE on exchange cancellation + outstanding sessions (for discussion):
--   The phase-2 sessions_guard only permits a session status change while the
--   parent exchange is 'accepted'. Therefore, to cancel an exchange that still
--   has a proposed/confirmed session, the client should cancel the SESSION
--   first (fires session_cancelled), then cancel the EXCHANGE (fires
--   exchange_cancelled). If you prefer the exchange-cancel to auto-void its
--   sessions atomically, that would be a small ADDITIVE trigger on exchanges
--   (AFTER UPDATE ... WHEN new.status='cancelled') — omitted here pending your
--   decision, to avoid changing the agreed phase-2 behavior without approval.
-- ============================================================================
-- End of Phase 3 migration.
-- ============================================================================
