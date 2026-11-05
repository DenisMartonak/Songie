-- Songies accounts, step 1: profiles, username check, account deletion and
-- the avatars bucket. Apply once (see docs/supabase.md).

-- Profiles ------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- 3 to 20 of a-z, 0-9, _ and . ; no . at the start or the end.
  constraint profiles_username_rule
    check (username ~ '^[a-z0-9_][a-z0-9_.]{1,18}[a-z0-9_]$')
);

create unique index profiles_username_lower_key
  on public.profiles (lower(username));

alter table public.profiles enable row level security;

create policy "Signed-in users can read profiles"
  on public.profiles for select
  to authenticated
  using (true);

create policy "Users can create their own profile"
  on public.profiles for insert
  to authenticated
  with check (id = (select auth.uid()));

create policy "Users can update their own profile"
  on public.profiles for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No delete policy: a profile goes only with its account (on delete cascade).

-- Table privileges: signed-out clients get nothing; signed-in clients may
-- change only the username and the picture (id and timestamps stay put).
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant insert (id, username, avatar_path) on table public.profiles to authenticated;
grant update (username, avatar_path) on table public.profiles to authenticated;

-- updated_at ----------------------------------------------------------------

create function public.profiles_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.profiles_set_updated_at() from public, anon, authenticated;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.profiles_set_updated_at();

-- Sign-up: create the profile from the sign-up metadata ---------------------

-- Runs in the same transaction as the auth.users insert. A missing, invalid
-- or taken username raises (not-null, check or unique violation), so the
-- sign-up fails and no account exists without a profile.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username)
  values (new.id, lower(new.raw_user_meta_data ->> 'username'));
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Username availability (callable signed out; reveals only true/false) -----

-- Lowercases the name first, as the sign-up trigger does.
create function public.username_available(name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    lower(name) ~ '^[a-z0-9_][a-z0-9_.]{1,18}[a-z0-9_]$'
      and not exists (
        select 1 from public.profiles p
        where lower(p.username) = lower(name)
      ),
    false
  );
$$;

revoke all on function public.username_available(text) from public, anon, authenticated;
grant execute on function public.username_available(text) to anon, authenticated;

-- Delete my account ----------------------------------------------------------

-- Deletes the caller's auth user; the profile goes by cascade. The app
-- deletes the caller's avatar files first.
create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon, authenticated;
grant execute on function public.delete_my_account() to authenticated;

-- Avatars bucket ---------------------------------------------------------------

-- Public read through public URLs. 256x256 JPEGs only, well under 1 MB.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg'])
on conflict (id) do nothing;

-- Writes only inside the caller's own folder: <user id>/<file>.
-- Select is needed too: Storage's update and delete read the row first.
create policy "avatars: users read their own folder"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars: users upload to their own folder"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars: users update their own files"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars: users delete their own files"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
