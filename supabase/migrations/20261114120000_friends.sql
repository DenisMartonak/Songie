-- Friends: two accounts become friends when one asks and the other accepts.
-- Apply once, after 20261113120000_saved_artists.sql (see docs/supabase.md).
--
-- One row per pair of accounts, either a request (pending, from requester to
-- addressee) or a friendship (accepted). Apps read only their own rows and
-- change them only through the security definer functions below.

-- Friendships ---------------------------------------------------------------------

-- Rows go with either account (on delete cascade). The unique index on the
-- unordered pair keeps A->B and B->A from both existing.
create table public.friendships (
  requester uuid not null references auth.users (id) on delete cascade,
  addressee uuid not null references auth.users (id) on delete cascade,
  status text not null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  primary key (requester, addressee),
  constraint friendships_not_self check (requester <> addressee),
  constraint friendships_status_rule check (status in ('pending', 'accepted'))
);

create unique index friendships_pair
  on public.friendships (least(requester, addressee), greatest(requester, addressee));

create index friendships_addressee on public.friendships (addressee);

-- Each account reads the rows it is in, and nothing else; no insert, update
-- or delete grant: the functions below make every change.
alter table public.friendships enable row level security;
revoke all on table public.friendships from anon, authenticated;
grant select on table public.friendships to authenticated;

create policy "friendships: users read their own rows"
  on public.friendships for select
  to authenticated
  using (requester = (select auth.uid()) or addressee = (select auth.uid()));

-- Requests ---------------------------------------------------------------------------

-- Serialises changes to one pair, so two crossed requests sent at once end as
-- one accepted row rather than a unique violation.
create function public.lock_friend_pair(a uuid, b uuid)
returns void
language sql
volatile
set search_path = ''
as $$
  select pg_advisory_xact_lock(
    hashtextextended(least(a, b)::text || greatest(a, b)::text, 0)
  );
$$;

revoke all on function public.lock_friend_pair(uuid, uuid) from public, anon, authenticated;

-- The caller asks p_other to be friends. Returns the pair's status after the
-- call: 'pending' for a new request, 'accepted' when p_other had already
-- asked the caller (the request is accepted), or the existing row's status
-- unchanged. Fails with self_request or unknown_user (no profile).
create function public.send_friend_request(p_other uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  f public.friendships;
begin
  if me is null then
    raise exception 'not_signed_in';
  end if;
  if p_other = me then
    raise exception 'self_request';
  end if;
  if not exists (select 1 from public.profiles p where p.id = p_other) then
    raise exception 'unknown_user';
  end if;

  perform public.lock_friend_pair(me, p_other);

  select * into f from public.friendships
    where (requester = me and addressee = p_other)
       or (requester = p_other and addressee = me);
  if found then
    if f.status = 'pending' and f.addressee = me then
      update public.friendships
        set status = 'accepted', accepted_at = now()
        where requester = f.requester and addressee = f.addressee;
      return 'accepted';
    end if;
    return f.status;
  end if;

  insert into public.friendships (requester, addressee, status)
    values (me, p_other, 'pending');
  return 'pending';
end;
$$;

-- The caller accepts p_other's request. Fails with not_requested when there is
-- no pending request from p_other to the caller.
create function public.accept_friend_request(p_other uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception 'not_signed_in';
  end if;

  perform public.lock_friend_pair(me, p_other);

  update public.friendships
    set status = 'accepted', accepted_at = now()
    where requester = p_other and addressee = me and status = 'pending';
  if not found then
    raise exception 'not_requested';
  end if;
end;
$$;

-- Deletes the pair's row, whichever way round and whatever its state: declines
-- or cancels a request, or ends a friendship. Nothing to delete is fine.
create function public.remove_friend(p_other uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception 'not_signed_in';
  end if;

  perform public.lock_friend_pair(me, p_other);

  delete from public.friendships
    where (requester = me and addressee = p_other)
       or (requester = p_other and addressee = me);
end;
$$;

revoke all on function public.send_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.accept_friend_request(uuid) from public, anon, authenticated;
revoke all on function public.remove_friend(uuid) from public, anon, authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
