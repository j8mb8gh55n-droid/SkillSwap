-- ============================================================================
-- SkillSwap — Phase D3 migration: Community Spotlight (RPC only)
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do NOT run until approved.
--
-- Adds ONE read-only SECURITY DEFINER function,
--   public.community_spotlight(target_month date default null),
-- that returns ONE featured student per positive recognition category for a
-- calendar month (default: the current Asia/Riyadh month). It is needed because:
--   * exchanges are RLS-restricted to their two participants, so a client can
--     never aggregate contributions across students; and
--   * the existing student_stats() RPC is LIFETIME and PER-STUDENT, so it
--     cannot produce monthly, cross-student recognition.
--
-- This is NOT a leaderboard: exactly ONE student is featured per category, the
-- categories measure CONTRIBUTION (completed exchanges / distinct peers / skills
-- taught), there are no public rankings, star ratings, or negative signals, and
-- nothing is ever fabricated — a category with no qualifier is simply omitted.
--
-- PARAMETER:
--   target_month date default null
--     * NULL  -> the current calendar month (evaluated in Asia/Riyadh).
--     * Any date -> that date's calendar month. The value is truncated to the
--       first of its month; the SAME month window drives every calculation
--       (completions, thresholds, and Rising Star age). Historical months are
--       therefore fully reproducible.
--
-- RECOGNITION CATEGORIES (all computed for the SELECTED Asia/Riyadh month):
--   helping_hand      -> most DISTINCT peers helped        (min 2 distinct peers)
--   knowledge_sharer  -> most DISTINCT skills taught        (min 2 distinct skills)
--   community_builder -> most completed exchanges           (min 2 completed)
--   rising_star       -> account at most 60 days old AS OF THE END of the
--                        selected month AND >= 1 verified completed exchange in
--                        that month (registration alone never qualifies; anyone
--                        who joined after the month cannot qualify).
--
-- ROLE-CORRECT skill/peer mapping (identical to student_stats):
--   * requester TEACHES offered_skill_id,  peer = recipient
--   * recipient TEACHES requested_skill_id, peer = requester
--
-- MONTHLY WINDOW:
--   * Boundaries from exchanges.completed_at ONLY (never created_at/updated_at).
--   * Calendar month in Asia/Riyadh, as a HALF-OPEN interval [m_start, m_end).
--   * Rows with completed_at IS NULL are excluded.
--
-- DETERMINISTIC TIE-BREAKING (no randomness; stable across identical data):
--   primary metric DESC -> a secondary contribution metric DESC
--   -> earliest contribution in the month ASC (first to contribute wins)
--   -> profile id ASC (final stable key).
--   (Previous-month recognition is permitted only as a tie-breaker; it is NOT
--    implemented here to keep the RPC minimal — the earliest-contribution + id
--    keys already make results fully deterministic. See the shipped audit.)
--
-- PRIVACY / SECURITY:
--   * Returns ONLY: the month, and per category the featured student's profile
--     id and an aggregate count. Never exchange rows, participant pairs, skill
--     ids, messages, or Kudos givers/identities.
--   * Featured students must meet the app's discoverability bar (an onboarded
--     profile with a non-empty full_name) — same gate StudentDiscovery uses.
--   * Results are GLOBAL (identical for every viewer); they never depend on the
--     caller, so the function does not filter by auth.uid().
--   * SECURITY DEFINER + fixed empty search_path + fully-qualified names.
--   * Executable by AUTHENTICATED users only (not anon/public). No service-role
--     key is ever used in the app.
--
-- COMPATIBILITY: additive and idempotent. Adds NO tables, triggers, scheduled
-- jobs, or policies, and changes NO existing RLS.
-- ============================================================================

-- Drop any earlier (parameterless or same-signature) version so no stale
-- overload remains and a no-arg call resolves unambiguously to the default.
drop function if exists public.community_spotlight();
drop function if exists public.community_spotlight(date);

create or replace function public.community_spotlight(target_month date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    tz          constant text := 'Asia/Riyadh';
    anchor_loc  timestamp;      -- a wall-clock instant inside the target month
    m_start_loc timestamp;      -- first instant of that month, Riyadh wall-clock
    m_start     timestamptz;    -- month start as an absolute instant
    m_end       timestamptz;    -- next month start (exclusive upper bound)
    result      jsonb;
begin
    -- Resolve the month to evaluate, always in Asia/Riyadh wall-clock terms.
    if target_month is null then
        anchor_loc := (now() at time zone tz);        -- current Riyadh month
    else
        anchor_loc := target_month::timestamp;        -- any day in the chosen month
    end if;

    -- Half-open Riyadh calendar-month window: [m_start, m_end).
    m_start_loc := date_trunc('month', anchor_loc);
    m_start     := m_start_loc                       at time zone tz;
    m_end       := (m_start_loc + interval '1 month') at time zone tz;

    with completed as (
        -- Verified completions in the selected month only. completed_at is set
        -- by the exchanges_guard trigger exactly at the mutual-completion
        -- handshake and is immutable thereafter; NULLs are excluded.
        select e.requester_id, e.recipient_id,
               e.offered_skill_id, e.requested_skill_id, e.completed_at
          from public.exchanges e
         where e.status = 'completed'
           and e.completed_at is not null
           and e.completed_at >= m_start
           and e.completed_at <  m_end
    ),
    participant as (
        -- One row per participant per completed exchange, with ROLE-CORRECT
        -- taught skill and the peer they exchanged with.
        select requester_id as student, recipient_id as peer,
               offered_skill_id  as taught_skill, completed_at
          from completed
        union all
        select recipient_id as student, requester_id as peer,
               requested_skill_id as taught_skill, completed_at
          from completed
    ),
    agg as (
        -- Per-student monthly contribution, limited to discoverable (onboarded)
        -- profiles. created_at is carried for Rising Star eligibility.
        select p.student,
               count(*)                       as completed_count,   -- exchanges this month
               count(distinct p.peer)         as distinct_peers,    -- students helped
               count(distinct p.taught_skill) as distinct_skills,   -- skills taught
               min(p.completed_at)            as first_at,          -- earliest contribution (tie-break)
               pr.created_at                  as created_at
          from participant p
          join public.profiles pr on pr.id = p.student
         where btrim(coalesce(pr.full_name, '')) <> ''
         group by p.student, pr.created_at
    ),
    helping_hand as (
        select student, distinct_peers as cnt
          from agg
         where distinct_peers >= 2
         order by distinct_peers desc, completed_count desc, first_at asc, student asc
         limit 1
    ),
    knowledge_sharer as (
        select student, distinct_skills as cnt
          from agg
         where distinct_skills >= 2
         order by distinct_skills desc, completed_count desc, first_at asc, student asc
         limit 1
    ),
    community_builder as (
        select student, completed_count as cnt
          from agg
         where completed_count >= 2
         order by completed_count desc, distinct_peers desc, first_at asc, student asc
         limit 1
    ),
    rising_star as (
        -- Account at most 60 days old as of the END of the selected month, and
        -- joined before the month ended (so anyone who joined after the month
        -- cannot qualify). Age is anchored to m_end, NOT to the execution date,
        -- so historical months are reproducible. Requires >= 1 completion.
        select student, completed_count as cnt
          from agg
         where completed_count >= 1
           and created_at >= (m_end - interval '60 days')
           and created_at <  m_end
         order by completed_count desc, distinct_peers desc, first_at asc, student asc
         limit 1
    ),
    cat as (
        select 'helping_hand'::text      as category, student, cnt, 1 as ord from helping_hand
        union all
        select 'knowledge_sharer'::text  as category, student, cnt, 2 as ord from knowledge_sharer
        union all
        select 'community_builder'::text as category, student, cnt, 3 as ord from community_builder
        union all
        select 'rising_star'::text       as category, student, cnt, 4 as ord from rising_star
    )
    select jsonb_build_object(
        'month', to_char(m_start_loc, 'YYYY-MM'),
        'spotlight', coalesce(
            (select jsonb_agg(
                        jsonb_build_object(
                            'category', category,
                            'student',  student,
                            'count',    cnt)
                        order by ord)
               from cat),
            '[]'::jsonb)
    )
    into result;

    return result;
end;
$$;

-- Executable ONLY by authenticated users (anon/public cannot call it).
revoke all on function public.community_spotlight(date) from public, anon, authenticated;
grant execute on function public.community_spotlight(date) to authenticated;

-- ----------------------------------------------------------------------------
-- OPTIONAL performance aid (NOT enabled — review before adding).
-- The month filter scans exchanges by (status, completed_at); existing indexes
-- are on (requester_id,status) / (recipient_id,status) and don't serve it. For
-- a university-sized dataset the sequential scan is negligible, so this is left
-- commented. If/when exchange volume grows, a partial index helps:
--
--   create index if not exists exchanges_completed_at_idx
--       on public.exchanges (completed_at)
--       where status = 'completed';
--
-- (An index is not a table/trigger/job/RLS change, but it is still schema DDL —
--  left off by default to honor the "minimal" directive.)
-- ============================================================================
-- End of Phase D3 (community spotlight) migration.
-- ============================================================================
