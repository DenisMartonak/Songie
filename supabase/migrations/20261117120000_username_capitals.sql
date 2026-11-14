-- Usernames may hold capitals (SON-37). A name is kept as typed ("Denis"),
-- and stays unique in any case: profiles_username_lower_key is already on
-- lower(username), so "Denis" and "denis" can't both exist. Existing names
-- are all lowercase and stay as they are.

-- 3 to 20 of letters, digits, _ and . ; no . at the start or the end.
alter table public.profiles
  drop constraint profiles_username_rule;

alter table public.profiles
  add constraint profiles_username_rule
    check (username ~ '^[A-Za-z0-9_][A-Za-z0-9_.]{1,18}[A-Za-z0-9_]$');

-- Sign-up: as in the accounts migration, but the profile gets the name as
-- typed; the expired-sign-up lookup still compares in any case.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  name text := new.raw_user_meta_data ->> 'username';
begin
  delete from auth.users u
  using public.profiles p
  where p.id = u.id
    and lower(p.username) = lower(name)
    and u.id <> new.id
    and u.email_confirmed_at is null
    and u.last_sign_in_at is null
    and coalesce(u.confirmation_sent_at, u.created_at)
      < now() - interval '1 hour';

  insert into public.profiles (id, username) values (new.id, name);
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;

-- username_available needs no change: it checks lower(name) against the
-- lowercase rule and compares lower(username), so any case works.
