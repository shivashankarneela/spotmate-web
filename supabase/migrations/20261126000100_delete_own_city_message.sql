create function public.delete_own_city_message(p_room uuid, p_message uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  with removed as (
    update public.hotspot_messages as messages
    set deleted_at = now(), body = 'Message deleted',
        media_path = null, media_kind = null
    where messages.id = p_message
      and messages.hotspot_id = p_room
      and messages.sender_id = (select auth.uid())
      and messages.deleted_at is null
      and exists (
        select 1 from public.hotspots as rooms
        where rooms.id = p_room and rooms.is_city_chat
      )
    returning 1
  )
  select exists (select 1 from removed);
$$;

revoke all on function public.delete_own_city_message(uuid, uuid) from public, anon;
grant execute on function public.delete_own_city_message(uuid, uuid) to authenticated;
