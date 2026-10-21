-- ============================================================================
-- SkillSwap — Phase 5 (OPTIONAL): populate profiles.full_name at sign-up
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do not run until approved.
--
-- The app passes the student's Full Name as Supabase Auth user metadata at
-- sign-up (auth.signUp(..., data: ["full_name": ...])). This migration teaches
-- the EXISTING handle_new_user() trigger to copy that metadata into the new
-- profiles row, so the name is present the moment the profile is created.
--
-- This is OPTIONAL: the app already backfills full_name on first authenticated
-- load (ProfileService), so the greeting/profile work WITHOUT this change. Run
-- it only if you'd prefer the name to be set server-side at creation time.
--
-- Safe by design:
--   * CREATE OR REPLACE only — does NOT change the profiles schema.
--   * ON CONFLICT (id) DO NOTHING — never overwrites an existing profile.
--   * full_name is NOT NULL DEFAULT '' in profiles, so COALESCE guards nulls.
--   * No RLS / permission changes.
--   * Does NOT touch profiles_setup.sql (which must NOT be run).
-- ============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

-- The existing `on_auth_user_created` trigger already calls handle_new_user();
-- CREATE OR REPLACE above updates it in place, so no trigger change is needed.
-- ============================================================================
