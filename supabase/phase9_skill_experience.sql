-- ============================================================================
-- SkillSwap — Phase D4 migration: Skill Experience Levels (additive column)
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do NOT run until approved.
--
-- Lets a student record an experience level for each skill they TEACH. This is
-- the SMALLEST possible change: ONE nullable column on the existing
-- public.student_skills table, plus a CHECK constraint. It adds NO new tables,
-- NO RLS/policy changes, NO triggers, NO jobs, and performs NO data migration.
--
-- APPROVED LEVELS (stored as stable slugs; the app maps them to display text):
--   'getting_started'  -> "Getting Started"
--   'comfortable'      -> "Comfortable"
--   'experienced'      -> "Experienced"
--
-- RULES ENFORCED BY THE CHECK:
--   * experience_level may be NULL (unset) — existing rows and any skill without
--     a chosen level stay NULL, so nothing breaks.
--   * A non-NULL level is allowed ONLY on TEACH rows (skill_type = 'teach').
--     Learning skills never carry a level (per the Phase D4 requirement).
--   * A non-NULL level must be one of the three approved slugs.
--
-- COMPATIBILITY (why this is safe & backward-compatible):
--   * ADD COLUMN IF NOT EXISTS is additive and idempotent; every existing
--     student_skills row gets experience_level = NULL.
--   * Current app inserts (student_id, skill_id, skill_type) keep working and
--     simply leave the column NULL until the app is updated to set it.
--   * Reads that don't select the column are unaffected.
--   * The existing UNIQUE(student_id, skill_id, skill_type) stays intact —
--     experience_level is a plain attribute, so a skill's level is updated in
--     place (or via the app's existing delete-then-insert save).
--   * Existing RLS on student_skills continues to govern all access unchanged
--     (owner writes own rows; authenticated reads as today). No policy touched.
-- ============================================================================

-- 1. Additive nullable column.
alter table public.student_skills
    add column if not exists experience_level text;

-- 2. Value + role guard (idempotent: drop our own constraint first, then add).
alter table public.student_skills
    drop constraint if exists student_skills_experience_level_chk;

alter table public.student_skills
    add constraint student_skills_experience_level_chk
    check (
        experience_level is null
        or (
            skill_type = 'teach'
            and experience_level in ('getting_started', 'comfortable', 'experienced')
        )
    );

-- ============================================================================
-- End of Phase D4 (skill experience levels) migration.
-- ============================================================================
