create or replace function public.music_seek_ten_seconds(p_room uuid,p_user uuid,p_direction text)
returns text language plpgsql security invoker set search_path = public,pg_temp as $$
declare r public.music_rooms%rowtype; position_ms bigint; target_ms integer;
begin
 select * into r from public.music_rooms where id=p_room for update;
 if not found or r.status <> 'active' or r.expires_at <= now() then raise exception 'Room is closed or expired'; end if;
 if r.room_kind <> 'music' or not exists (select 1 from public.music_room_members where room_id=p_room and user_id=p_user) then raise exception 'Join the music room first'; end if;
 if r.current_source_type is distinct from 'youtube' or r.current_source_ref is null then raise exception 'This stream does not support seeking'; end if;
 if p_direction not in ('forward','backward') then raise exception 'Invalid direction'; end if;
 position_ms := coalesce(r.seek_offset_ms,0) + case when r.is_playing then greatest(0,floor(extract(epoch from (now()-coalesce(r.started_at,now())))*1000)::bigint) else 0 end;
 target_ms := least(86400000,greatest(0,position_ms + case when p_direction='forward' then 10000 else -10000 end))::integer;
 update public.music_rooms set seek_offset_ms=target_ms,started_at=now() where id=p_room;
 return case when p_direction='forward' then 'Forward 10 seconds.' else 'Back 10 seconds.' end;
end $$;
revoke all on function public.music_seek_ten_seconds(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.music_seek_ten_seconds(uuid,uuid,text) to service_role;