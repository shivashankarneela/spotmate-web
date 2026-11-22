alter table public.music_rooms add column if not exists room_kind text not null default 'music' check (room_kind in ('music','tv'));
create or replace function public.create_tv_room(p_host uuid,p_title text,p_name text,p_avatar text,p_duration integer,p_custom boolean)
returns public.music_rooms language plpgsql security invoker set search_path=public,pg_temp as $$
declare room public.music_rooms;
begin
 if p_custom then room := public.music_create_custom_room(p_host,p_name,p_avatar,p_title,p_duration);
 else room := public.create_free_listening_room(p_host,p_title,p_name,p_avatar); end if;
 update public.music_rooms set room_kind='tv' where id=room.id returning * into room;
 delete from public.music_room_messages where room_id=room.id and kind='bot';
 return room;
end $$;
create or replace function public.tv_room_change_channel(p_room uuid,p_user uuid,p_video_id text,p_title text)
returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare r public.music_rooms;
begin
 select * into r from public.music_rooms where id=p_room for update;
 if not found or r.room_kind <> 'tv' or r.status <> 'active' or r.expires_at <= now() then raise exception 'Room closed or expired'; end if;
 if not exists(select 1 from public.music_room_members where room_id=p_room and user_id=p_user) then raise exception 'Join the room before changing channels'; end if;
 if p_video_id !~ '^[A-Za-z0-9_-]{11}$' or length(p_title)>300 then raise exception 'Invalid channel'; end if;
 update public.music_rooms set current_source_type='youtube',current_source_ref=p_video_id,current_title=p_title,started_at=now(),seek_offset_ms=0,is_playing=true where id=p_room;
end $$;
create or replace function public.tv_room_leave(p_room uuid,p_user uuid)
returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare r public.music_rooms; next_host uuid;
begin
 select * into r from public.music_rooms where id=p_room for update;
 if not found or r.room_kind <> 'tv' then raise exception 'TV room not found'; end if;
 delete from public.music_room_members where room_id=p_room and user_id=p_user;
 select user_id into next_host from public.music_room_members where room_id=p_room order by joined_at,user_id limit 1;
 if next_host is null then update public.music_rooms set status='closed',is_playing=false,closed_at=now() where id=p_room;
 elsif r.host_user_id=p_user then update public.music_rooms set host_user_id=next_host where id=p_room; end if;
end $$;
revoke all on function public.create_tv_room(uuid,text,text,text,integer,boolean),public.tv_room_change_channel(uuid,uuid,text,text),public.tv_room_leave(uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_tv_room(uuid,text,text,text,integer,boolean),public.tv_room_change_channel(uuid,uuid,text,text),public.tv_room_leave(uuid,uuid) to service_role;
