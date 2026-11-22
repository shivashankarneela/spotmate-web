create or replace function public.music_member_control(
  p_room uuid, p_user uuid, p_action text,
  p_source_type text default null, p_source_ref text default null, p_title text default null
) returns text
language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  r public.music_rooms%rowtype;
  next_track public.music_room_queue%rowtype;
  result text;
begin
  select * into r from public.music_rooms where id = p_room for update;
  if not found or r.status <> 'active' or r.expires_at <= now() then
    raise exception 'Room is closed or expired';
  end if;
  if not exists (select 1 from public.music_room_members where room_id = p_room and user_id = p_user) then
    raise exception 'Join the room before controlling playback';
  end if;
  case p_action
    when 'play' then
      if p_source_type not in ('youtube', 'hls_audio') or p_source_ref is null or p_title is null then
        raise exception 'Invalid track';
      end if;
      if r.current_source_ref is null then
        update public.music_rooms set current_source_type=p_source_type, current_source_ref=p_source_ref,
          current_title=p_title, started_at=now(), seek_offset_ms=0, is_playing=true where id=p_room;
        result := 'Now playing: ' || p_title;
      else
        insert into public.music_room_queue(room_id, added_by, source_type, source_ref, title, status)
        values(p_room, p_user, p_source_type, p_source_ref, p_title, 'queued');
        result := 'Queued: ' || p_title;
      end if;
    when 'pause' then
      if r.current_source_ref is null then return 'Nothing is playing.'; end if;
      if r.is_playing then
        update public.music_rooms set is_playing=false,
          seek_offset_ms=least(86400000, greatest(0, coalesce(r.seek_offset_ms,0) +
            floor(extract(epoch from (now()-coalesce(r.started_at,now()))) * 1000)::integer)) where id=p_room;
      end if;
      result := 'Playback paused.';
    when 'resume' then
      if r.current_source_ref is null then return 'Nothing is playing.'; end if;
      if not r.is_playing then
        update public.music_rooms set is_playing=true, started_at=now() where id=p_room;
      end if;
      result := 'Playback resumed.';
    when 'skip' then
      select * into next_track from public.music_room_queue where room_id=p_room and status='queued'
        order by created_at, id limit 1 for update;
      if found then
        update public.music_room_queue set status='playing' where id=next_track.id;
        update public.music_rooms set current_source_type=next_track.source_type, current_source_ref=next_track.source_ref,
          current_title=next_track.title, started_at=now(), seek_offset_ms=0, is_playing=true where id=p_room;
        result := 'Now playing: ' || next_track.title;
      else
        update public.music_rooms set current_source_type=null, current_source_ref=null, current_title=null,
          started_at=null, seek_offset_ms=0, is_playing=false where id=p_room;
        result := 'Queue is empty.';
      end if;
    when 'stop' then
      update public.music_room_queue set status='skipped' where room_id=p_room and status='queued';
      update public.music_rooms set current_source_type=null, current_source_ref=null, current_title=null,
        started_at=null, seek_offset_ms=0, is_playing=false where id=p_room;
      result := 'Playback stopped and queue cleared.';
    else raise exception 'Unknown playback action';
  end case;
  return result;
end;
$$;
revoke all on function public.music_member_control(uuid,uuid,text,text,text,text) from public, anon, authenticated;
grant execute on function public.music_member_control(uuid,uuid,text,text,text,text) to service_role;
