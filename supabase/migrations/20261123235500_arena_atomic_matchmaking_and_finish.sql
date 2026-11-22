create or replace function public.arena_pair_queue_atomic(
  p_entries uuid[], p_players jsonb, p_state jsonb, p_turn uuid, p_turn_seconds integer
) returns public.arena_game_matches language plpgsql security invoker set search_path=public,pg_temp as $$
declare first_row public.arena_matchmaking_queue; m public.arena_game_matches; ids uuid[]; total integer;
begin
  if coalesce(array_length(p_entries,1),0) not between 2 and 4 or jsonb_typeof(p_players)<>'array'
     or jsonb_array_length(p_players)<>array_length(p_entries,1) or p_turn_seconds<1 or p_turn_seconds>3600 then
    raise exception 'Invalid matchmaking request';
  end if;
  perform id from public.arena_matchmaking_queue where id=any(p_entries) order by id for update;
  select * into first_row from public.arena_matchmaking_queue where id=p_entries[1];
  if not found then return null; end if;
  select count(*),array_agg(user_id order by array_position(p_entries,id)) into total,ids
    from public.arena_matchmaking_queue where id=any(p_entries) and status='waiting' and expires_at>now()
    and game_type=first_row.game_type and player_count=first_row.player_count and stake_sc=first_row.stake_sc;
  if total<>array_length(p_entries,1) or total<>first_row.player_count then return null; end if;
  if p_turn is not null and not(p_turn=any(ids)) then raise exception 'Invalid first player'; end if;
  for total in 1..array_length(ids,1) loop
    if (p_players->(total-1)->>'user_id')::uuid is distinct from ids[total] then
      raise exception 'Player information changed';
    end if;
  end loop;
  insert into public.arena_game_matches(game_type,source_mode,stake_sc,pot_sc,player_ids,players_meta,state_json,turn_user_id,turn_expires_at)
    values(first_row.game_type,'random_queue',first_row.stake_sc,first_row.stake_sc*array_length(ids,1),ids,p_players,p_state,p_turn,now()+make_interval(secs=>p_turn_seconds))
    returning * into m;
  if first_row.stake_sc>0 then perform public.arena_lock_match_escrow(m.id,ids,first_row.stake_sc); end if;
  update public.arena_matchmaking_queue set status='matched',matched_id=m.id where id=any(p_entries);
  return m;
end $$;

create or replace function public.arena_finish_match_atomic(
  p_match uuid,p_actor uuid,p_expected timestamptz,p_final_status text,p_winner uuid,p_reason text,p_state jsonb,p_timeout boolean default false
) returns public.arena_game_matches language plpgsql security invoker set search_path=public,pg_temp as $$
declare m public.arena_game_matches; state jsonb; summary jsonb; outcome text;
begin
  select * into m from public.arena_game_matches where id=p_match for update;
  if not found or not(p_actor=any(m.player_ids)) then raise exception 'Match not found'; end if;
  if m.status<>'active' or m.updated_at is distinct from p_expected then raise exception 'Match state changed. Refresh and try again'; end if;
  if p_timeout and m.turn_expires_at>now() then raise exception 'Turn has not expired'; end if;
  if p_final_status not in ('completed','draw','forfeit') or (p_winner is not null and not(p_winner=any(m.player_ids))) then
    raise exception 'Invalid result';
  end if;
  state:=p_state;
  if m.game_type='chess' and state->>'white_id' is not null and state->>'black_id' is not null then
    outcome:=case when p_final_status='draw' or p_winner is null then 'draw'
      when p_winner::text=state->>'white_id' then 'white' else 'black' end;
    summary:=public.arena_update_chess_elo((state->>'white_id')::uuid,(state->>'black_id')::uuid,outcome);
    state:=state || jsonb_build_object('elo_summary',summary);
  end if;
  perform * from public.arena_settle_match(p_match,p_final_status,p_winner,p_reason,state);
  select * into m from public.arena_game_matches where id=p_match;
  return m;
end $$;
revoke all on function public.arena_pair_queue_atomic(uuid[],jsonb,jsonb,uuid,integer),
  public.arena_finish_match_atomic(uuid,uuid,timestamptz,text,uuid,text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.arena_pair_queue_atomic(uuid[],jsonb,jsonb,uuid,integer),
  public.arena_finish_match_atomic(uuid,uuid,timestamptz,text,uuid,text,jsonb,boolean) to service_role;
