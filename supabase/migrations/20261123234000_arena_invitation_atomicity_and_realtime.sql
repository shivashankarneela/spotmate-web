create or replace function public.arena_is_match_participant(p_match uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select auth.uid() is not null and exists(
    select 1 from public.arena_game_matches m where m.id=p_match and auth.uid()=any(m.player_ids)
  )
$$;
revoke all on function public.arena_is_match_participant(uuid) from public,anon;
grant execute on function public.arena_is_match_participant(uuid) to authenticated,service_role;

drop policy if exists "match_chat_read_participants" on public.arena_match_messages;
create policy "match_chat_read_participants" on public.arena_match_messages for select to authenticated
  using (public.arena_is_match_participant(match_id));
drop policy if exists "match_chat_insert_participants" on public.arena_match_messages;
create policy "match_chat_insert_participants" on public.arena_match_messages for insert to authenticated
  with check (user_id=auth.uid() and public.arena_is_match_participant(match_id));

create or replace function public.arena_accept_challenge_atomic(
  p_challenge uuid, p_user uuid, p_players jsonb, p_state jsonb, p_turn uuid, p_turn_seconds integer
) returns public.arena_game_matches language plpgsql security invoker set search_path=public,pg_temp as $$
declare c public.arena_game_challenges; m public.arena_game_matches; ids uuid[];
begin
  select * into c from public.arena_game_challenges where id=p_challenge for update;
  if not found or c.to_user_id<>p_user then raise exception 'Challenge not found'; end if;
  if c.status='accepted' and c.match_id is not null then
    select * into m from public.arena_game_matches where id=c.match_id;
    if found then return m; end if;
    raise exception 'Accepted match unavailable';
  end if;
  if c.status<>'pending' or c.expires_at<=now() then raise exception 'Challenge expired or already answered'; end if;
  ids := array[c.from_user_id,c.to_user_id];
  if p_turn_seconds<1 or p_turn_seconds>3600 or (p_turn is not null and not(p_turn=any(ids))) or jsonb_typeof(p_players)<>'array' or jsonb_array_length(p_players)<>2 then
    raise exception 'Invalid match configuration';
  end if;
  insert into public.arena_game_matches(game_type,source_mode,stake_sc,pot_sc,player_ids,players_meta,state_json,turn_user_id,turn_expires_at)
    values(c.game_type,'spotmate_id',c.stake_sc,c.stake_sc*2,ids,p_players,p_state,p_turn,now()+make_interval(secs=>p_turn_seconds))
    returning * into m;
  if c.stake_sc>0 then perform public.arena_lock_match_escrow(m.id,ids,c.stake_sc); end if;
  update public.arena_game_challenges set status='accepted',match_id=m.id where id=c.id;
  return m;
end $$;
revoke all on function public.arena_accept_challenge_atomic(uuid,uuid,jsonb,jsonb,uuid,integer) from public,anon,authenticated;
grant execute on function public.arena_accept_challenge_atomic(uuid,uuid,jsonb,jsonb,uuid,integer) to service_role;

do $$
declare t text;
begin
 foreach t in array array['arena_game_challenges','arena_matchmaking_queue','arena_match_messages'] loop
   if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
     execute format('alter publication supabase_realtime add table public.%I',t);
   end if;
 end loop;
end $$;
