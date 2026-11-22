revoke all on public.room_game_sessions_public from public, anon, authenticated;
grant select on public.room_game_sessions_public to service_role;
revoke all on function public.ping_live_tv_viewer(uuid),public.record_spotmate_reel_share(uuid,uuid,text,text),public.toggle_spotmate_reel_like(uuid) from public,anon;
grant execute on function public.ping_live_tv_viewer(uuid),public.record_spotmate_reel_share(uuid,uuid,text,text),public.toggle_spotmate_reel_like(uuid) to authenticated,service_role;
alter function public.ping_live_tv_viewer(uuid) set search_path = public, pg_temp;
