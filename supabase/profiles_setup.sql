-- SkillSwap — profiles table setup
-- Run this in the Supabase dashboard (SQL Editor) once.
-- It is idempotent: safe to run more than once.

-- 1. Add the three skill/availability columns the app needs.
--    (id, full_name, major, bio, avatar_url already exist.)
alter table public.profiles add column if not exists teaching_skills text;
alter table public.profiles add column if not exists learning_skills text;
alter table public.profiles add column if not exists availability    text;

-- 2. Row Level Security: each student can only read/create/update their OWN row.
--    (Skip this block if you have already configured RLS to your liking.)
alter table public.profiles enable row level security;

drop policy if exists "Profiles are viewable by their owner" on public.profiles;
create policy "Profiles are viewable by their owner"
  on public.profiles for select
  using ( auth.uid() = id );

drop policy if exists "Users can insert their own profile" on public.profiles;
create policy "Users can insert their own profile"
  on public.profiles for insert
  with check ( auth.uid() = id );

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update
  using ( auth.uid() = id )
  with check ( auth.uid() = id );

-- 3. (Optional but recommended) Auto-create a profile row when a user signs up,
--    so the row always exists. The app also upserts defensively, so this is optional.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
