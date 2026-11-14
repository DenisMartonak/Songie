-- Profile redesign (SON-39): friends can see whether an account shares its
-- stats, how many friends it has, and a bigger stats payload. Apply once,
-- after 20261115120000_friend_activity.sql (see docs/supabase.md).

-- The caller's stats (top artists/songs and totals) now fit in 64 kB; over
-- that fails with too_large. Nothing happens while the caller does not share.
create or replace function public.publish_top(p_top jsonb)
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
  if octet_length(p_top::text) > 65536 then
    raise exception 'too_large';
  end if;
  insert into public.activity (user_id, top, top_updated_at)
    values (me, p_top, now())
  on conflict (user_id) do update
    set top = excluded.top,
        top_updated_at = excluded.top_updated_at
    where public.activity.share_top;
end;
$$;

-- Same as before, plus share_top (the flag itself, unmasked) so the app can
-- tell a friend who hides their stats from one who has none yet.
drop function public.friend_activity();

create function public.friend_activity()
returns table (
  user_id uuid,
  now_playing jsonb,
  now_updated_at timestamptz,
  room_code text,
  top jsonb,
  share_top boolean
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
    case when a.share_top then a.top end,
    a.share_top
  from public.friendships f
  join public.activity a
    on a.user_id = case
      when f.requester = (select auth.uid()) then f.addressee
      else f.requester
    end
  where f.status = 'accepted'
    and (f.requester = (select auth.uid()) or f.addressee = (select auth.uid()));
$$;

-- How many friends p_user has: for the caller, or for one of the caller's
-- friends; null for anyone else.
create function public.friend_count(p_user uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_user = (select auth.uid()) or exists (
      select 1 from public.friendships m
      where m.status = 'accepted'
        and ((m.requester = (select auth.uid()) and m.addressee = p_user)
          or (m.addressee = (select auth.uid()) and m.requester = p_user))
    ) then (
      select count(*)::integer from public.friendships f
      where f.status = 'accepted'
        and (f.requester = p_user or f.addressee = p_user)
    )
  end;
$$;

revoke all on function public.publish_top(jsonb) from public, anon, authenticated;
revoke all on function public.friend_activity() from public, anon, authenticated;
revoke all on function public.friend_count(uuid) from public, anon, authenticated;
grant execute on function public.publish_top(jsonb) to authenticated;
grant execute on function public.friend_activity() to authenticated;
grant execute on function public.friend_count(uuid) to authenticated;
