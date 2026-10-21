-- ============================================================================
-- SkillSwap — Phase D5 migration: Availability Status (accepting new exchanges?)
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do NOT run until approved.
--
-- Lets a student say whether they are currently accepting NEW skill exchanges.
-- This is SEPARATE from weekly availability (the availability table of days +
-- time ranges is NOT touched).
--
-- Two parts:
--   (A) SMALLEST data change — ONE additive column on public.profiles.
--   (B) BACKEND ENFORCEMENT — extends the EXISTING exchanges_validate_insert
--       trigger function so an 'unavailable' recipient cannot receive new
--       requests even if a client bypasses the disabled button. This is a
--       trigger modification and therefore REQUIRES EXPLICIT APPROVAL before
--       running (per the Phase D5 security + DB-safety rules).
--
-- APPROVED STATUSES (stored as stable slugs):
--   'open'         -> "Open"        (accepting new requests)
--   'limited'      -> "Limited"     (accepting new requests)
--   'unavailable'  -> "Unavailable" (NOT accepting new requests)
--
-- COMPATIBILITY:
--   * (A) is additive. NOT NULL DEFAULT 'open' backfills every existing profile
--     to 'open' automatically, so the default status is Open and no existing
--     row breaks. No RLS/policy change; profiles' existing SELECT/UPDATE policies
--     continue to govern who can read/update it (a student updates only their
--     own row, as today).
--   * (B) adds ONE guard to the existing BEFORE INSERT trigger. It fires only on
--     NEW exchange creation and only blocks when the recipient is 'unavailable'.
--     'open'/'limited' (incl. every back-filled row) are unaffected, so current
--     behavior is unchanged for everyone who hasn't chosen 'unavailable'.
--   * (B) does NOT touch existing/pending/accepted exchanges and NEVER cancels
--     anything — it only governs inserts. All other validations are preserved
--     verbatim. No RLS policy is altered.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (A) Additive column on profiles.
-- ----------------------------------------------------------------------------
alter table public.profiles
    add column if not exists availability_status text not null default 'open';

alter table public.profiles
    drop constraint if exists profiles_availability_status_chk;

alter table public.profiles
    add constraint profiles_availability_status_chk
    check (availability_status in ('open', 'limited', 'unavailable'));

-- ----------------------------------------------------------------------------
-- (B) Backend enforcement — extend the existing exchange-insert validator.
--     Identical to the current function PLUS one guard: reject inserts whose
--     recipient is 'unavailable'. SECURITY DEFINER + empty search_path +
--     fully-qualified names are preserved. The trigger binding is unchanged.
-- ----------------------------------------------------------------------------
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

    -- NEW (Phase D5): the recipient must currently be accepting requests.
    if (select p.availability_status
          from public.profiles p
         where p.id = new.recipient_id) = 'unavailable' then
        raise exception 'This student is not accepting new exchange requests right now';
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

-- (Trigger binding unchanged — re-declared for idempotency/safety.)
drop trigger if exists exchanges_validate_insert_t on public.exchanges;
create trigger exchanges_validate_insert_t
    before insert on public.exchanges
    for each row execute function public.exchanges_validate_insert();

-- ============================================================================
-- End of Phase D5 (availability status) migration.
-- ============================================================================
