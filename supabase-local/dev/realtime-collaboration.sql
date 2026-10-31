create or replace function public.board_id_from_realtime_topic(channel_topic text)
returns uuid
language plpgsql
immutable
set search_path = public
as $$
begin
  if channel_topic !~ '^board:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return null;
  end if;
  return split_part(channel_topic, ':', 2)::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

drop policy if exists "Board members can receive realtime collaboration." on realtime.messages;
create policy "Board members can receive realtime collaboration."
  on realtime.messages for select
  to public
  using (
    extension in ('broadcast', 'presence')
    and public.board_access_permission(public.board_id_from_realtime_topic(realtime.topic())) in ('owner', 'read', 'write')
  );

drop policy if exists "Board members can send realtime collaboration." on realtime.messages;
create policy "Board members can send realtime collaboration."
  on realtime.messages for insert
  to public
  with check (
    extension in ('broadcast', 'presence')
    and public.board_access_permission(public.board_id_from_realtime_topic(realtime.topic())) in ('owner', 'read', 'write')
  );
