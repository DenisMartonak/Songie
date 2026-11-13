-- Friend activity: what each account is listening to now, the room it hosts,
-- and its top 10 of the last 30 days, shown to its friends. Apply once, after
-- 20261114120000_friends.sql (see docs/supabase.md).
--
-- One row per account. The account's own devices write it only through the
-- security definer functions below; friends read it only through
-- friend_activity(), which leaves out whatever the account does not share.

-- Activity ----------------------------------------------------------------------------

-- share_listening covers now_playing, now_updated_at and room_code; share_top
-- covers top and top_updated_at. Both start on. Turning one off clears what it
-- covers (set_sharing), and publishing what it covers does nothing while off.
create table public.activity (
  user_id uuid primary key references auth.users (id) on delete cascade,
  share_listening boolean not null default true,
  share_top boolean not null default true,
  -- {"title", "artist", "videoId"?}
  now_playing jsonb,
  now_updated_at timestamptz,
  room_code text,
  -- {"artists": [{"name"}], "songs": [{"title", "artist", "videoId"?}]}
  top jsonb,
  top_updated_at timestamptz
);

-- An account reads its own row; friends go through friend_activity().
alter table public.activity enable row level security;
revoke all on table public.activity from anon, authenticated;
grant select on table public.activity to authenticated;

create policy "activity: users read their own row"
  on public.activity for select
  to authenticated
  using (user_id = (select auth.uid()));

-- Whether a and b are friends (an accepted request either way). Not callable
-- by apps.
create function public.are_friends(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester = a and f.addressee = b)
        or (f.requester = b and f.addressee = a))
  );
$$;

revoke all on function public.are_friends(uuid, uuid) from public, anon, authenticated;

-- Sharing ------------------------------------------------------------------------------

-- The caller's two switches; both on when the account has no row yet.
create function public.my_sharing()
returns table (share_listening boolean, share_top boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(a.share_listening, true), coalesce(a.share_top, true)
  from (select 1) as one
  left join public.activity a on a.user_id = (select auth.uid());
$$;

-- Sets the caller's switches; one turned off clears what it covers.
create function public.set_sharing(p_listening boolean, p_top boolean)
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
  insert into public.activity (user_id, share_listening, share_top)
    values (me, p_listening, p_top)
  on conflict (user_id) do update
    set share_listening = excluded.share_listening,
        share_top = excluded.share_top;
  if not p_listening then
    update public.activity
      set now_playing = null, now_updated_at = null, room_code = null
      where user_id = me;
  end if;
  if not p_top then
    update public.activity
      set top = null, top_updated_at = null
      where user_id = me;
  end if;
end;
$$;

-- Publishing ---------------------------------------------------------------------------

-- What the caller plays now (null: nothing) and the code of the room it hosts
-- (null: none). Nothing happens while the caller does not share listening.
create function public.publish_now_playing(p_now jsonb, p_room_code text)
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
  insert into public.activity (user_id, now_playing, now_updated_at, room_code)
    values (me, p_now, now(), p_room_code)
  on conflict (user_id) do update
    set now_playing = excluded.now_playing,
        now_updated_at = excluded.now_updated_at,
        room_code = excluded.room_code
    where public.activity.share_listening;
end;
$$;

-- The caller's top 10 of the last 30 days. Nothing happens while the caller
-- does not share it.
create function public.publish_top(p_top jsonb)
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
  insert into public.activity (user_id, top, top_updated_at)
    values (me, p_top, now())
  on conflict (user_id) do update
    set top = excluded.top,
        top_updated_at = excluded.top_updated_at
    where public.activity.share_top;
end;
$$;

-- Reading ------------------------------------------------------------------------------

-- The caller's friends' activity: one row per friend that has a row, each
-- part only when that friend shares it.
create function public.friend_activity()
returns table (
  user_id uuid,
  now_playing jsonb,
  now_updated_at timestamptz,
  room_code text,
  top jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select a.user_id,
    case when a.share_listening then a.now_playing end,
    case when a.share_listening then a.now_updated_at end,
    case when a.share_listening then a.room_code end,
    case when a.share_top then a.top end
  from public.activity a
  where public.are_friends((select auth.uid()), a.user_id);
$$;

revoke all on function public.my_sharing() from public, anon, authenticated;
revoke all on function public.set_sharing(boolean, boolean) from public, anon, authenticated;
revoke all on function public.publish_now_playing(jsonb, text) from public, anon, authenticated;
revoke all on function public.publish_top(jsonb) from public, anon, authenticated;
revoke all on function public.friend_activity() from public, anon, authenticated;
grant execute on function public.my_sharing() to authenticated;
grant execute on function public.set_sharing(boolean, boolean) to authenticated;
grant execute on function public.publish_now_playing(jsonb, text) to authenticated;
grant execute on function public.publish_top(jsonb) to authenticated;
grant execute on function public.friend_activity() to authenticated;
