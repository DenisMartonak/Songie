-- Listen together: a host opens a room, friends join by code, and everyone in
-- it hears the same song. Apply once, after 20261107120000_remote_control.sql
-- (see docs/supabase.md).
--
-- The room itself (who is in it, whether it is open) lives in two tables that
-- only the functions below touch. What happens inside a room (the playing
-- state, requests, who may control) travels over the private Realtime topic
-- room:<room id> and is stored nowhere. Realtime checks the policies at the
-- end of this file on realtime.messages with realtime.topic() set to the topic.

-- Rooms ------------------------------------------------------------------------

-- code is the 8 characters a guest types (shown as XXXX-XXXX, stored without
-- the dash), from an alphabet without 0, O, 1, I and L. A room is open until
-- ended_at is set, or for 24 hours after created_at, whichever comes first.
create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  host_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  constraint rooms_code_rule check (code ~ '^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{8}$')
);

create index rooms_host on public.rooms (host_id);

-- Everyone in a room, the host included (at most 10, enforced by join_room).
-- Rows go with the room or with the account.
create table public.room_members (
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create index room_members_user on public.room_members (user_id);

-- No policy and no grant on either table: every read and write goes through
-- the security definer functions below.
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
revoke all on table public.rooms from anon, authenticated;
revoke all on table public.room_members from anon, authenticated;

-- Open ---------------------------------------------------------------------------

-- A new room hosted by the caller, who is its first member. The caller's
-- other open rooms end first, so a host has one room at a time. The code is
-- random; on the rare clash with another code, try again.
create function public.open_room()
returns table (room_id uuid, code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  new_code text;
  new_id uuid;
begin
  if me is null then
    raise exception 'not_signed_in';
  end if;

  perform public.end_room(r.id) from public.rooms r
    where r.host_id = me and r.ended_at is null;

  for attempt in 1..10 loop
    new_code := '';
    for i in 1..8 loop
      new_code := new_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    begin
      insert into public.rooms (code, host_id) values (new_code, me)
        returning id into new_id;
      exit;
    exception when unique_violation then
      new_id := null;
    end;
  end loop;
  if new_id is null then
    raise exception 'no_free_code';
  end if;

  insert into public.room_members (room_id, user_id) values (new_id, me);
  return query select new_id, new_code;
end;
$$;

-- Join ---------------------------------------------------------------------------

-- Adds the caller to the open room with this code and returns its id. The
-- message of the exception says why not: room_not_found, room_ended (ended,
-- or created over 24 hours ago) or room_full (10 members). Joining again is
-- fine and changes nothing.
create function public.join_room(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  r public.rooms;
begin
  if me is null then
    raise exception 'not_signed_in';
  end if;

  -- Lock the room's row so two guests joining at once can't both take the
  -- last place.
  select * into r from public.rooms
    where code = upper(replace(coalesce(p_code, ''), '-', ''))
    for update;
  if not found then
    raise exception 'room_not_found';
  end if;
  if r.ended_at is not null or r.created_at < now() - interval '24 hours' then
    raise exception 'room_ended';
  end if;

  if not exists (
    select 1 from public.room_members m where m.room_id = r.id and m.user_id = me
  ) then
    if (select count(*) from public.room_members m where m.room_id = r.id) >= 10 then
      raise exception 'room_full';
    end if;
    insert into public.room_members (room_id, user_id) values (r.id, me);
  end if;
  return r.id;
end;
$$;

-- Leave, remove, end ------------------------------------------------------------

-- The caller leaves a room. The host leaving is the same as ending it.
create function public.leave_room(p_room uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if exists (select 1 from public.rooms r where r.id = p_room and r.host_id = me) then
    perform public.end_room(p_room);
  else
    delete from public.room_members m where m.room_id = p_room and m.user_id = me;
  end if;
end;
$$;

-- The host removes a guest (never themselves; they end the room instead).
create function public.remove_member(p_room uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.rooms r
    where r.id = p_room and r.host_id = (select auth.uid()) and r.ended_at is null
  ) then
    raise exception 'not_host';
  end if;
  delete from public.room_members m
    where m.room_id = p_room and m.user_id = p_user
      and m.user_id <> (select auth.uid());
end;
$$;

-- The host ends the room: it stops being open and loses its members, so
-- nobody can join or use its topic any more.
create function public.end_room(p_room uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.rooms r
    where r.id = p_room and r.host_id = (select auth.uid())
  ) then
    raise exception 'not_host';
  end if;
  update public.rooms set ended_at = coalesce(ended_at, now()) where id = p_room;
  delete from public.room_members m where m.room_id = p_room;
end;
$$;

revoke all on function public.open_room() from public, anon, authenticated;
revoke all on function public.join_room(text) from public, anon, authenticated;
revoke all on function public.leave_room(uuid) from public, anon, authenticated;
revoke all on function public.remove_member(uuid, uuid) from public, anon, authenticated;
revoke all on function public.end_room(uuid) from public, anon, authenticated;
grant execute on function public.open_room() to authenticated;
grant execute on function public.join_room(text) to authenticated;
grant execute on function public.leave_room(uuid) to authenticated;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.end_room(uuid) to authenticated;

-- Realtime -----------------------------------------------------------------------

-- Room id of a topic named room:<uuid>, else null. Not callable by apps.
create function public.room_of_topic(topic text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when topic ~ '^room:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then substr(topic, 6)::uuid
  end;
$$;

-- Whether the caller is a member of the open room on this topic, and whether
-- they are its host. Security definer because the tables have no policies;
-- the policies below call them for the signed-in user only.
create function public.is_room_member(topic text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.room_members m
    join public.rooms r on r.id = m.room_id
    where m.room_id = public.room_of_topic(topic)
      and m.user_id = (select auth.uid())
      and r.ended_at is null
  );
$$;

create function public.is_room_host(topic text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.rooms r
    where r.id = public.room_of_topic(topic)
      and r.host_id = (select auth.uid())
      and r.ended_at is null
  );
$$;

revoke all on function public.room_of_topic(text) from public, anon, authenticated;
revoke all on function public.is_room_member(text) from public, anon, authenticated;
revoke all on function public.is_room_host(text) from public, anon, authenticated;
grant execute on function public.room_of_topic(text) to authenticated;
grant execute on function public.is_room_member(text) to authenticated;
grant execute on function public.is_room_host(text) to authenticated;

-- A member of an open room may receive on room:<room id>, and send Broadcast
-- and Presence on it. Only the host may send the events that change what
-- everyone hears: state, roles, kick and end. Guests send request (and
-- Presence). The server does not look at the `from` device id inside a
-- request; rooms are for friends.
create policy "room: members receive on their room topic"
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and (select realtime.topic()) = realtime.messages.topic
    and (select public.is_room_member((select realtime.topic())))
  );

create policy "room: members send on their room topic"
  on realtime.messages for insert
  to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and (select realtime.topic()) = realtime.messages.topic
    and (select public.is_room_member((select realtime.topic())))
    and (
      realtime.messages.event is null
      or realtime.messages.event not in ('state', 'roles', 'kick', 'end')
      or (select public.is_room_host((select realtime.topic())))
    )
  );
