create or replace function public.create_free_listening_room(p_host uuid,p_title text,p_name text,p_avatar text)
returns public.music_rooms language plpgsql set search_path=public as $$
declare room music_rooms;
begin
  insert into music_rooms(room_code,title,mode,duration_minutes,cost_sc,max_members,host_user_id,expires_at)
  values(generate_music_room_code(),p_title,'free',30,0,5,p_host,now()+interval '30 minutes') returning * into room;
  insert into music_room_members(room_id,user_id,display_name,avatar_url) values(room.id,p_host,p_name,p_avatar);
  return room;
end $$;
create or replace function public.transfer_free_music_host(p_room uuid,p_actor uuid,p_next uuid)
returns void language plpgsql set search_path=public as $$
declare room music_rooms; person music_room_members;
begin
  select * into room from music_rooms where id=p_room for update;
  if room.id is null or room.mode<>'free' or room.status<>'active' or room.expires_at<=now() or room.host_user_id<>p_actor then
    raise exception 'Only the current host of an active free room can transfer hosting';
  end if;
  select * into person from music_room_members where room_id=p_room and user_id=p_next;
  if not found then raise exception 'Choose a listener in this room'; end if;
  if p_next=p_actor then return; end if;
  update music_rooms set host_user_id=p_next where id=p_room;
  insert into music_room_messages(room_id,display_name,kind,content) values(p_room,'MusicBot','bot',person.display_name||' is now the room host.');
end $$;
revoke all on function public.create_free_listening_room(uuid,text,text,text),public.transfer_free_music_host(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_free_listening_room(uuid,text,text,text),public.transfer_free_music_host(uuid,uuid,uuid) to service_role;
