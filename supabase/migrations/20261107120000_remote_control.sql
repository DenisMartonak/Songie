-- Remote control: a signed-in user's devices control each other over the
-- private Realtime topic remote:<user id> (Presence for who is online,
-- Broadcast for state, commands and hello). Nothing is stored: there is no
-- table, so nothing here to read, leak or clean up when an account is
-- deleted. The only server-side piece is who may join and send.
--
-- Realtime checks these policies on realtime.messages with
-- realtime.topic() set to the topic. A signed-in user may receive and send
-- (Broadcast and Presence) only on remote:<their id>. The sync:<user id>
-- topic and its policy are unchanged.
create policy "remote: users receive on their own remote topic"
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and (select realtime.topic()) = 'remote:' || (select auth.uid())::text
    and realtime.messages.topic = (select realtime.topic())
  );

create policy "remote: users send on their own remote topic"
  on realtime.messages for insert
  to authenticated
  with check (
    realtime.messages.extension in ('broadcast', 'presence')
    and (select realtime.topic()) = 'remote:' || (select auth.uid())::text
    and realtime.messages.topic = (select realtime.topic())
  );
