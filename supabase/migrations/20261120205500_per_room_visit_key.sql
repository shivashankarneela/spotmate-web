alter table private.city_visits drop constraint city_visits_pkey,
 add primary key(user_id,session_id,room_id);
create or replace function public.city_visit(p_room uuid, p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); sid uuid:=(auth.jwt()->>'session_id')::uuid;
 v private.city_visits; t timestamptz; live boolean;
begin
 if u is null or sid is null then raise exception 'Sign in required'; end if;
 if not exists(select 1 from public.hotspots where id=p_room and is_city_chat and status='approved')
 or not private.is_active_hotspot_member(p_room) then raise exception 'Enter this city room first'; end if;
 perform pg_advisory_xact_lock(hashtextextended(u::text,2));
 t:=clock_timestamp();
 select * into v from private.city_visits where user_id=u and session_id=sid and room_id=p_room;
 live:=found and v.room_id=p_room and v.session_id=sid and v.last_action>t-interval '5 minutes';
 if p_action in ('open','join') and not live then
   if p_action='open' and v.room_id=p_room and v.session_id=sid then return null; end if;
   insert into private.city_visits values(u,sid,p_room,t,t,t)
   on conflict(user_id,session_id,room_id) do update set session_id=sid,room_id=p_room,joined_at=t,visible_from=t,last_action=t returning * into v;
 elsif p_action='leave' then
   delete from private.city_visits where user_id=u and room_id=p_room and session_id=sid;
   return null;
 elsif not live then return null;
 elsif p_action in ('touch','clear','join') then
   update private.city_visits set last_action=t,visible_from=case when p_action='clear' then t else visible_from end where user_id=u and session_id=sid and room_id=p_room returning * into v;
 elsif p_action not in ('open','check') then raise exception 'Unknown visit action';
 end if;
 return jsonb_build_object('joined',v.joined_at,'remaining_ms',greatest(0,extract(epoch from (v.last_action+interval '5 minutes'-t))*1000));
end $$;
