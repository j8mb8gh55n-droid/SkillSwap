-- ============================================================================
-- SkillSwap — Phase D2 migration: verified student statistics (RPC only)
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do not run until approved.
--
-- Adds ONE read-only SECURITY DEFINER function, public.student_stats(student),
-- that returns ONLY aggregate numbers for a student's PUBLIC statistics and
-- achievement thresholds. It is needed because exchanges are RLS-restricted to
-- participants, so a viewer cannot read another student's exchanges directly.
--
-- Returns (jsonb, counts only — never ids, messages, or giver identities):
--   completed_swaps        -> completed exchanges involving the student
--   skills_shared          -> DISTINCT skills the student TAUGHT (role-correct)
--   students_helped        -> DISTINCT other participants in completed exchanges
--   skills_explored        -> DISTINCT skills the student LEARNED (role-correct)
--   kudos_distinct_givers  -> DISTINCT givers of received kudos (for SkillSwap Star)
--
-- "Kudos Received" (total) is intentionally NOT here — the app reuses the
-- existing public.kudos_count(student) RPC for that (per the Phase D2 brief).
--
-- Does NOT add tables, stored progress, badge state, triggers, or jobs. Does
-- NOT modify exchanges/kudos/profiles or their policies. Additive and
-- idempotent (CREATE OR REPLACE).
--
-- Security: SECURITY DEFINER + empty search_path + fully-qualified names;
-- rejects NULL input; executable ONLY by authenticated users (not anon/public).
-- Taught/learned skill for a given exchange is role-correct:
--   * requester teaches offered_skill_id, learns requested_skill_id
--   * recipient teaches requested_skill_id, learns offered_skill_id
-- ============================================================================

create or replace function public.student_stats(student uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    result jsonb;
begin
    if student is null then
        raise exception 'student id is required';
    end if;

    with completed as (
        select e.requester_id, e.recipient_id, e.offered_skill_id, e.requested_skill_id
          from public.exchanges e
         where e.status = 'completed'
           and (e.requester_id = student or e.recipient_id = student)
    ),
    taught as (
        select distinct
               case when requester_id = student then offered_skill_id else requested_skill_id end as sid
          from completed
    ),
    learned as (
        select distinct
               case when requester_id = student then requested_skill_id else offered_skill_id end as sid
          from completed
    ),
    others as (
        select distinct
               case when requester_id = student then recipient_id else requester_id end as oid
          from completed
    )
    select jsonb_build_object(
        'completed_swaps',       (select count(*) from completed),
        'skills_shared',         (select count(*) from taught),
        'students_helped',       (select count(*) from others),
        'skills_explored',       (select count(*) from learned),
        'kudos_distinct_givers', (select count(distinct k.giver_id)
                                    from public.kudos k
                                   where k.recipient_id = student)
    )
    into result;

    return result;
end;
$$;

revoke all on function public.student_stats(uuid) from public, anon, authenticated;
grant execute on function public.student_stats(uuid) to authenticated;

-- ============================================================================
-- End of Phase D2 (student stats) migration.
-- ============================================================================
