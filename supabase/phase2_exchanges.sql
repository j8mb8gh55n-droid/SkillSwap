-- ============================================================================
-- SkillSwap — Phase 2 migration: exchanges + sessions  (REVISED)
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do not run until approved.
--
-- Adds two new tables and their security. Does NOT modify or replace the
-- existing tables (profiles, skills, student_skills, availability) or their
-- policies/triggers. Safe to run once.
--
-- Database-level guarantees (maps to approved requirements):
--   1  self-exchange blocked              -> CHECK (requester_id <> recipient_id)
--   2  only recipient accepts/declines    -> exchanges_guard
--   3  only requester cancels pending      -> exchanges_guard
--   4  either participant cancels accepted -> exchanges_guard
--   5  only participants can access        -> RLS select/update
--   6  participants & skills immutable      -> exchanges_guard
--   7  skills match actual teach skills     -> exchanges_validate_insert (definer)
--   8  only participants propose sessions on accepted exchanges
--                                           -> sessions RLS + sessions_validate_insert
--   9  only the OTHER participant confirms a session -> sessions_guard
--   10 completion needs BOTH confirmations + eligible session -> exchanges_guard
--   11 no forging the other's confirmation  -> exchanges_guard (owner-only flag)
--   12 completed rows frozen                -> exchanges_guard (terminal immutable)
--   13 no hard delete                       -> no DELETE policy/grant
--
-- Additional hardening in this revision:
--   * New sessions always start 'proposed'; proposed_by must be the caller.
--   * Session identity/details immutable after creation (reschedule = new row).
--   * Exchange metadata (goal/format/message) and all timestamps immutable /
--     database-controlled after creation.
--   * Session changes blocked unless the parent exchange is still 'accepted'.
--   * Partial unique index blocks duplicate pending requests.
--   * SECURITY DEFINER function uses an empty search_path and fully-qualified
--     names; EXECUTE revoked from PUBLIC on all trigger functions.
--   * Completion/cancellation race closed with SELECT ... FOR UPDATE on the
--     eligible session (see exchanges_guard).
--   * Primary key `id` is immutable on both tables (cannot be repointed).
--   * DELETE explicitly revoked from anon/authenticated (belt-and-suspenders
--     with the no-DELETE-policy rule) so history cannot be hard-deleted.
--
-- KNOWN LIMITATION — ACCOUNT DELETION (documented, NOT implemented here):
--   The FK references to public.profiles(id) use ON DELETE CASCADE. If a
--   profile (auth user) is ever deleted, all of that user's exchanges and the
--   sessions beneath them are deleted too — including the OTHER participant's
--   view of completed history. We are NOT implementing account deletion or a
--   soft-delete/anonymization design in this migration; this note records the
--   behavior so it is a conscious, reviewed choice. Changing it later (e.g. to
--   preserve history) would be a separate, additive migration.
-- ============================================================================

create extension if not exists pgcrypto;   -- for gen_random_uuid()

-- ----------------------------------------------------------------------------
-- 1. exchanges
-- ----------------------------------------------------------------------------
create table if not exists public.exchanges (
    id                  uuid        primary key default gen_random_uuid(),
    requester_id        uuid        not null references public.profiles(id) on delete cascade,
    recipient_id        uuid        not null references public.profiles(id) on delete cascade,
    offered_skill_id    bigint      not null references public.skills(id),
    requested_skill_id  bigint      not null references public.skills(id),
    learning_goal       text,
    preferred_format    text        not null default 'no_preference'
                        check (preferred_format in ('online','in_person','no_preference')),
    message             text,
    status              text        not null default 'pending'
                        check (status in ('pending','accepted','declined','completed','cancelled')),
    requester_completed boolean     not null default false,
    recipient_completed boolean     not null default false,
    created_at          timestamptz not null default now(),
    updated_at          timestamptz not null default now(),
    responded_at        timestamptz,
    completed_at        timestamptz,
    constraint exchanges_not_self check (requester_id <> recipient_id)
);

create index if not exists exchanges_recipient_status_idx
    on public.exchanges (recipient_id, status);
create index if not exists exchanges_requester_status_idx
    on public.exchanges (requester_id, status);

-- Requirement 5: block duplicate *pending* requests for the same
-- requester/recipient/offered/requested combination. Because it is partial
-- (status = 'pending'), a new request is allowed once a prior one is
-- accepted/declined/cancelled/completed, and different skill combinations are
-- always allowed.
create unique index if not exists exchanges_unique_pending_idx
    on public.exchanges (requester_id, recipient_id, offered_skill_id, requested_skill_id)
    where status = 'pending';

-- ----------------------------------------------------------------------------
-- 2. sessions
-- ----------------------------------------------------------------------------
create table if not exists public.sessions (
    id                uuid        primary key default gen_random_uuid(),
    exchange_id       uuid        not null references public.exchanges(id) on delete cascade,
    scheduled_at      timestamptz not null,
    duration_minutes  int         not null default 60 check (duration_minutes > 0),
    format            text        not null check (format in ('online','in_person')),
    location_or_link  text,
    status            text        not null default 'proposed'
                      check (status in ('proposed','confirmed','cancelled')),
    proposed_by       uuid        not null references public.profiles(id),
    created_at        timestamptz not null default now(),
    updated_at        timestamptz not null default now()
);

create index if not exists sessions_exchange_idx
    on public.sessions (exchange_id);

-- ----------------------------------------------------------------------------
-- 3. Row Level Security
-- ----------------------------------------------------------------------------
alter table public.exchanges enable row level security;
alter table public.sessions  enable row level security;

-- No DELETE is granted (requirement 13: preserve history; cancel via status).
grant select, insert, update on public.exchanges to authenticated;
grant select, insert, update on public.sessions  to authenticated;

-- Defense in depth for requirement 13: some Supabase projects auto-grant ALL
-- privileges (including DELETE) to anon/authenticated via ALTER DEFAULT
-- PRIVILEGES. RLS already blocks deletes (there is no DELETE policy), but we
-- also revoke the privilege explicitly so history can never be hard-deleted
-- through the API. (REVOKE of a privilege not held is a harmless no-op.)
revoke delete on public.exchanges from authenticated, anon;
revoke delete on public.sessions  from authenticated, anon;

-- exchanges policies -----------------------------------------------------------
drop policy if exists exchanges_select on public.exchanges;
create policy exchanges_select
    on public.exchanges for select to authenticated
    using ( auth.uid() = requester_id or auth.uid() = recipient_id );

drop policy if exists exchanges_insert on public.exchanges;
create policy exchanges_insert
    on public.exchanges for insert to authenticated
    with check ( auth.uid() = requester_id and requester_id <> recipient_id );

drop policy if exists exchanges_update on public.exchanges;
create policy exchanges_update
    on public.exchanges for update to authenticated
    using ( auth.uid() = requester_id or auth.uid() = recipient_id )
    with check ( auth.uid() = requester_id or auth.uid() = recipient_id );
-- (WHO may do WHAT, and which fields may change, is enforced by exchanges_guard.)

-- sessions policies ------------------------------------------------------------
drop policy if exists sessions_select on public.sessions;
create policy sessions_select
    on public.sessions for select to authenticated
    using (
        exists (
            select 1 from public.exchanges e
            where e.id = exchange_id
              and ( auth.uid() = e.requester_id or auth.uid() = e.recipient_id )
        )
    );

-- Insert allowed only by a participant of an ACCEPTED exchange, as themselves.
-- (sessions_validate_insert additionally forces status = 'proposed'.)
drop policy if exists sessions_insert on public.sessions;
create policy sessions_insert
    on public.sessions for insert to authenticated
    with check (
        proposed_by = auth.uid()
        and exists (
            select 1 from public.exchanges e
            where e.id = exchange_id
              and e.status = 'accepted'
              and ( auth.uid() = e.requester_id or auth.uid() = e.recipient_id )
        )
    );

drop policy if exists sessions_update on public.sessions;
create policy sessions_update
    on public.sessions for update to authenticated
    using (
        exists (
            select 1 from public.exchanges e
            where e.id = exchange_id
              and ( auth.uid() = e.requester_id or auth.uid() = e.recipient_id )
        )
    )
    with check (
        exists (
            select 1 from public.exchanges e
            where e.id = exchange_id
              and ( auth.uid() = e.requester_id or auth.uid() = e.recipient_id )
        )
    );
-- (Confirm-by-other-only, cancel rules, immutability, and parent-status checks
--  are enforced by sessions_guard.)

-- ----------------------------------------------------------------------------
-- 4. Security functions & triggers
-- ----------------------------------------------------------------------------

-- 4a. Validate a new exchange's skills correspond to real teach skills (req 7),
--     and force a clean initial state. SECURITY DEFINER so it can read the
--     recipient's student_skills even if that table is tightened later; empty
--     search_path + fully-qualified names prevent search-path hijacking.
create or replace function public.exchanges_validate_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    if not exists (
        select 1 from public.student_skills ss
        where ss.student_id = new.requester_id
          and ss.skill_id   = new.offered_skill_id
          and ss.skill_type = 'teach'
    ) then
        raise exception 'Offered skill must be a skill you teach';
    end if;

    if not exists (
        select 1 from public.student_skills ss
        where ss.student_id = new.recipient_id
          and ss.skill_id   = new.requested_skill_id
          and ss.skill_type = 'teach'
    ) then
        raise exception 'Requested skill must be a skill the recipient teaches';
    end if;

    -- Clean, server-controlled starting state regardless of client input.
    new.status              := 'pending';
    new.requester_completed := false;
    new.recipient_completed := false;
    new.responded_at        := null;
    new.completed_at        := null;
    new.created_at          := now();
    new.updated_at          := now();
    return new;
end;
$$;

revoke all on function public.exchanges_validate_insert() from public;

drop trigger if exists exchanges_validate_insert_t on public.exchanges;
create trigger exchanges_validate_insert_t
    before insert on public.exchanges
    for each row execute function public.exchanges_validate_insert();

-- 4b. Guard every exchange UPDATE: immutability, transitions, and the mutual
--     completion handshake (reqs 2,3,4,6,10,11,12). SECURITY INVOKER — it acts
--     as the caller; participants can already read their own sessions.
create or replace function public.exchanges_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
    actor uuid := auth.uid();
begin
    -- Immutable identifiers (req 6). Includes the primary key so a client can
    -- never repoint the row.
    if new.id                  is distinct from old.id
       or new.requester_id     is distinct from old.requester_id
       or new.recipient_id     is distinct from old.recipient_id
       or new.offered_skill_id   is distinct from old.offered_skill_id
       or new.requested_skill_id is distinct from old.requested_skill_id then
        raise exception 'Exchange identity, participants, and skills cannot be changed';
    end if;

    -- Immutable metadata set once at creation (req 3).
    if new.learning_goal    is distinct from old.learning_goal
       or new.preferred_format is distinct from old.preferred_format
       or new.message          is distinct from old.message then
        raise exception 'Exchange details (goal, format, message) cannot be changed after creation';
    end if;

    -- Timestamps are database-controlled: ignore any client-supplied values.
    -- (responded_at / completed_at are (re)set below by the transition logic.)
    new.created_at   := old.created_at;
    new.responded_at := old.responded_at;
    new.completed_at := old.completed_at;

    -- Terminal states are frozen (reqs 12 & 13).
    if old.status = 'completed' then
        raise exception 'Completed exchanges cannot be modified';
    end if;
    if old.status in ('declined','cancelled') then
        raise exception 'This exchange is closed and cannot be modified';
    end if;

    -- Completion flags: owner-only, one-way (reqs 10,11).
    if new.requester_completed is distinct from old.requester_completed then
        if new.requester_completed = false then
            raise exception 'A completion confirmation cannot be withdrawn';
        end if;
        if actor is distinct from old.requester_id then
            raise exception 'You may only submit your own completion confirmation';
        end if;
    end if;

    if new.recipient_completed is distinct from old.recipient_completed then
        if new.recipient_completed = false then
            raise exception 'A completion confirmation cannot be withdrawn';
        end if;
        if actor is distinct from old.recipient_id then
            raise exception 'You may only submit your own completion confirmation';
        end if;
    end if;

    -- A newly-set completion flag requires an accepted exchange AND an eligible
    -- (confirmed, already-occurred) session (req 10).
    if (new.requester_completed and not old.requester_completed)
       or (new.recipient_completed and not old.recipient_completed) then

        if old.status <> 'accepted' then
            raise exception 'Completion can only be confirmed on an accepted exchange';
        end if;

        -- Concurrency fix (req 2): take a row lock (FOR UPDATE) on the eligible
        -- session(s). This serializes against a concurrent session cancellation:
        --   * If completion runs first, it locks the session; a concurrent
        --     cancel blocks until this commits, then fails because the parent
        --     is no longer 'accepted'.
        --   * If the cancel runs first, this SELECT blocks until it commits,
        --     then re-reads and finds no 'confirmed' session -> FOUND is false
        --     and completion is refused.
        -- No deadlock: this path locks the exchange row then the session row;
        -- the cancel path locks the session row and only *reads* the exchange.
        perform 1
           from public.sessions s
          where s.exchange_id = old.id
            and s.status = 'confirmed'
            and s.scheduled_at <= now()
          for update;

        if not found then
            raise exception 'Completion requires a confirmed session that has already taken place';
        end if;
    end if;

    -- Explicit status transitions (reqs 2,3,4).
    if new.status is distinct from old.status then
        if old.status = 'pending' and new.status = 'accepted' then
            if actor is distinct from old.recipient_id then
                raise exception 'Only the recipient can accept a request';
            end if;
            new.responded_at := now();

        elsif old.status = 'pending' and new.status = 'declined' then
            if actor is distinct from old.recipient_id then
                raise exception 'Only the recipient can decline a request';
            end if;
            new.responded_at := now();

        elsif old.status = 'pending' and new.status = 'cancelled' then
            if actor is distinct from old.requester_id then
                raise exception 'Only the requester can cancel a pending request';
            end if;

        elsif old.status = 'accepted' and new.status = 'cancelled' then
            if actor is distinct from old.requester_id
               and actor is distinct from old.recipient_id then
                raise exception 'Only a participant can cancel an exchange';
            end if;

        else
            raise exception 'Invalid status transition from % to %', old.status, new.status;
        end if;
    end if;

    -- Mutual completion handshake: flip to completed only when BOTH confirm.
    if new.requester_completed and new.recipient_completed and new.status = 'accepted' then
        new.status       := 'completed';
        new.completed_at := now();
    end if;

    new.updated_at := now();
    return new;
end;
$$;

revoke all on function public.exchanges_guard() from public;

drop trigger if exists exchanges_guard_t on public.exchanges;
create trigger exchanges_guard_t
    before update on public.exchanges
    for each row execute function public.exchanges_guard();

-- 4c. Validate a new session (req 1 & 8): always 'proposed', proposed_by is the
--     caller, parent exchange is accepted and the caller is a participant.
create or replace function public.sessions_validate_insert()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
    actor uuid := auth.uid();
begin
    if new.proposed_by is distinct from actor then
        raise exception 'You can only propose a session as yourself';
    end if;

    if not exists (
        select 1 from public.exchanges e
        where e.id = new.exchange_id
          and e.status = 'accepted'
          and ( actor = e.requester_id or actor = e.recipient_id )
    ) then
        raise exception 'Sessions can only be proposed on your own accepted exchanges';
    end if;

    -- Server-controlled: a new session can never start confirmed or cancelled.
    new.status     := 'proposed';
    new.created_at := now();
    new.updated_at := now();
    return new;
end;
$$;

revoke all on function public.sessions_validate_insert() from public;

drop trigger if exists sessions_validate_insert_t on public.sessions;
create trigger sessions_validate_insert_t
    before insert on public.sessions
    for each row execute function public.sessions_validate_insert();

-- 4d. Guard session UPDATE (reqs 2-protect, 4, 9): identity/details immutable,
--     parent exchange must still be accepted, only the OTHER participant may
--     confirm, either participant may cancel.
create or replace function public.sessions_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
    actor            uuid := auth.uid();
    parent_status    text;
    other_participant uuid;
begin
    -- Immutable session identity & proposal details (req 2-protect).
    if new.id               is distinct from old.id
       or new.exchange_id      is distinct from old.exchange_id
       or new.proposed_by      is distinct from old.proposed_by
       or new.scheduled_at     is distinct from old.scheduled_at
       or new.duration_minutes is distinct from old.duration_minutes
       or new.format           is distinct from old.format
       or new.location_or_link is distinct from old.location_or_link then
        raise exception 'Session details cannot be changed; propose a new session instead';
    end if;

    -- Database-controlled timestamp.
    new.created_at := old.created_at;

    -- Parent exchange must still be accepted for ANY session change (req 4).
    select e.status,
           case when old.proposed_by = e.requester_id then e.recipient_id
                else e.requester_id end
      into parent_status, other_participant
      from public.exchanges e
     where e.id = old.exchange_id;

    if parent_status is distinct from 'accepted' then
        raise exception 'Sessions can only be changed while the exchange is accepted';
    end if;

    -- Status transitions.
    if new.status is distinct from old.status then
        if old.status = 'proposed' and new.status = 'confirmed' then
            if actor is distinct from other_participant then
                raise exception 'Only the other participant can confirm this session';
            end if;

        elsif new.status = 'cancelled' and old.status in ('proposed','confirmed') then
            if actor is distinct from old.proposed_by
               and actor is distinct from other_participant then
                raise exception 'Only a participant can cancel this session';
            end if;

        else
            raise exception 'Invalid session status transition from % to %', old.status, new.status;
        end if;
    end if;

    new.updated_at := now();
    return new;
end;
$$;

revoke all on function public.sessions_guard() from public;

drop trigger if exists sessions_guard_t on public.sessions;
create trigger sessions_guard_t
    before update on public.sessions
    for each row execute function public.sessions_guard();

-- ============================================================================
-- End of Phase 2 migration (revised).
-- ============================================================================
