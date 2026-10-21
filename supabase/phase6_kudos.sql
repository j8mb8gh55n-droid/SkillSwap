-- ============================================================================
-- SkillSwap — Phase D1 migration: Kudos (positive appreciation)
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do not run until approved.
--
-- Adds ONE new table (public.kudos) + RLS + a validation trigger. Does NOT
-- modify exchanges/profiles/sessions or their policies. Depends on the existing
-- exchanges + profiles tables. Safe to run once (IF NOT EXISTS / OR REPLACE).
--
-- Rules (map to the Phase D1 requirements):
--   * A kudos belongs to a COMPLETED exchange            -> trigger (status='completed')
--   * Giver is a participant; recipient is the OTHER one -> trigger
--   * Giver is the authenticated caller                  -> RLS insert + trigger
--   * One kudos per participant per exchange             -> UNIQUE (exchange_id, giver_id)
--   * No self-kudos                                       -> CHECK + trigger
--   * Only for completed (not pending/accepted/etc.)      -> trigger
--   * Multiple predefined appreciation tags               -> text[] + containment CHECK
--   * Optional short positive message                     -> nullable + length CHECK
--   * No editing another user's (or any) kudos            -> no UPDATE/DELETE granted/policy
--   * Duplicate prevention server-side                    -> UNIQUE constraint
--   * No service-role key in the app                      -> all via RLS as the authed user
--
-- PRIVACY MODEL (approved):
--   * Kudos ROWS (incl. the optional message) are readable ONLY by the two
--     participants: the giver (their own) and the recipient (what they received).
--   * Everyone else sees ONLY an aggregate count, via the SECURITY DEFINER
--     function public.kudos_count(student) — never rows, givers, or messages.
-- ============================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid()

-- ----------------------------------------------------------------------------
-- 1. kudos table
-- ----------------------------------------------------------------------------
create table if not exists public.kudos (
    id            uuid        primary key default gen_random_uuid(),
    exchange_id   uuid        not null references public.exchanges(id) on delete cascade,
    giver_id      uuid        not null references public.profiles(id)  on delete cascade,
    recipient_id  uuid        not null references public.profiles(id)  on delete cascade,
    tags          text[]      not null,
    message       text,
    created_at    timestamptz not null default now(),

    constraint kudos_not_self        check (giver_id <> recipient_id),
    -- cardinality() returns 0 for '{}' (array_length returns NULL, which would
    -- make the CHECK pass) — so this correctly rejects an empty tag array.
    constraint kudos_tags_nonempty   check (cardinality(tags) >= 1),
    -- Predefined appreciation tags only (matches the app's existing vibes).
    constraint kudos_tags_allowed    check (
        tags <@ array[
            'Patient teacher',
            'Super clear',
            'Really kind',
            'Great energy',
            'Went the extra mile'
        ]::text[]
    ),
    constraint kudos_message_len     check (message is null or char_length(message) <= 300),
    -- One kudos per participant per exchange (duplicate prevention).
    constraint kudos_one_per_giver   unique (exchange_id, giver_id)
);

create index if not exists kudos_recipient_idx on public.kudos (recipient_id);

-- ----------------------------------------------------------------------------
-- 2. Row Level Security
-- ----------------------------------------------------------------------------
alter table public.kudos enable row level security;

-- Participants read their own rows; insert as yourself. No update/delete
-- (kudos are immutable — nobody can edit anyone's kudos, including their own).
grant select, insert on public.kudos to authenticated;
revoke update, delete on public.kudos from authenticated, anon;

-- Only the giver (their own) and the recipient (what they received, incl. the
-- message) may read a kudos row. Aggregate counts for other students' profiles
-- go through kudos_count() below, NOT this policy.
drop policy if exists kudos_select on public.kudos;
create policy kudos_select
    on public.kudos for select to authenticated
    using ( giver_id = auth.uid() or recipient_id = auth.uid() );

drop policy if exists kudos_insert on public.kudos;
create policy kudos_insert
    on public.kudos for insert to authenticated
    with check ( giver_id = auth.uid() );

-- ----------------------------------------------------------------------------
-- 3. Validation trigger (BEFORE INSERT)
--    SECURITY DEFINER so it can read the parent exchange even under tight RLS;
--    empty search_path + fully-qualified names prevent search-path hijacking.
-- ----------------------------------------------------------------------------
create or replace function public.kudos_validate_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor uuid := auth.uid();
    req   uuid;
    rec   uuid;
    st    text;
begin
    if new.giver_id is distinct from actor then
        raise exception 'You can only give kudos as yourself';
    end if;

    select e.requester_id, e.recipient_id, e.status
      into req, rec, st
      from public.exchanges e
     where e.id = new.exchange_id;

    if not found then
        raise exception 'Exchange not found';
    end if;

    if st is distinct from 'completed' then
        raise exception 'Kudos can only be given for a completed exchange';
    end if;

    -- Giver must be one participant and recipient the OTHER one.
    if not ((new.giver_id = req and new.recipient_id = rec)
         or (new.giver_id = rec and new.recipient_id = req)) then
        raise exception 'Kudos must be between the two participants of this exchange';
    end if;

    new.created_at := now();
    return new;
end;
$$;

-- Trigger-only function: no role needs direct EXECUTE (the trigger runs it).
revoke all on function public.kudos_validate_insert() from public, anon, authenticated;

drop trigger if exists kudos_validate_insert_t on public.kudos;
create trigger kudos_validate_insert_t
    before insert on public.kudos
    for each row execute function public.kudos_validate_insert();

-- ----------------------------------------------------------------------------
-- 4. Public aggregate count (SECURITY DEFINER)
--    Returns ONLY the number of kudos a student has received — never rows,
--    givers, or messages. Used for profile display. Callable by any
--    authenticated user; anon cannot call it. The underlying rows remain
--    protected by the SELECT policy above (this function bypasses RLS only to
--    count, and returns a single integer). Fixed empty search_path + qualified
--    names for search-path safety.
-- ----------------------------------------------------------------------------
create or replace function public.kudos_count(student uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
    if student is null then
        raise exception 'student id is required';
    end if;
    return (select count(*)::int from public.kudos where recipient_id = student);
end;
$$;

-- Executable ONLY by authenticated users (anon/public cannot call it).
revoke all on function public.kudos_count(uuid) from public, anon, authenticated;
grant execute on function public.kudos_count(uuid) to authenticated;

-- ============================================================================
-- End of Phase D1 (kudos) migration.
-- ============================================================================
