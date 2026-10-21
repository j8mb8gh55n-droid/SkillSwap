-- ============================================================================
-- SkillSwap — Phase 4: avatar storage (Supabase Storage)
-- ----------------------------------------------------------------------------
-- FOR REVIEW ONLY. Do not run until approved.
--
-- Creates a public "avatars" bucket and RLS policies so a signed-in user may
-- upload/replace ONLY their own avatar (stored under "<user_id>/avatar.jpg"),
-- while anyone may read avatars (public profile images). The app writes the
-- resulting public URL into the existing profiles.avatar_url column — no new
-- columns, no schema changes to profiles.
--
-- Prerequisite for the in-app "Change profile photo" feature (EditProfileView
-- → ProfileService.uploadAvatar). Until this is applied the upload call will
-- fail and the user keeps their previous avatar (the app surfaces the error).
-- ============================================================================

-- 1. Public bucket for avatars (idempotent).
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 2. Policies on storage.objects, scoped to the avatars bucket.
--    Path convention: "<auth.uid()>/avatar.jpg" — the first path segment is
--    the owner's user id, which is what we check.

-- Public read of avatars.
drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read"
    on storage.objects for select
    using ( bucket_id = 'avatars' );

-- Insert only into your own folder.
drop policy if exists "avatars_insert_own" on storage.objects;
create policy "avatars_insert_own"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- Update only your own objects.
drop policy if exists "avatars_update_own" on storage.objects;
create policy "avatars_update_own"
    on storage.objects for update to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
    )
    with check (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- Delete only your own objects.
drop policy if exists "avatars_delete_own" on storage.objects;
create policy "avatars_delete_own"
    on storage.objects for delete to authenticated
    using (
        bucket_id = 'avatars'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

-- ============================================================================
-- End of Phase 4 storage setup.
-- ============================================================================
