create table public.chat_game_series (
  room_id text primary key,
  game_type text not null,
  running boolean not null,
  generation uuid not null default gen_random_uuid(),
  since_at timestamptz not null default clock_timestamp()
);
alter table public.chat_game_series enable row level security;
alter table public.room_game_sessions add column series_generation uuid, add column finished_at timestamptz;
create function public.stamp_chat_game_finish() returns trigger language plpgsql as $$
begin
  if old.status='active' and new.status<>'active' then new.finished_at=clock_timestamp(); end if;
  return new;
end $$;
create trigger stamp_chat_game_finish before update of status on public.room_game_sessions
for each row execute function public.stamp_chat_game_finish();
create index chat_game_results_by_room on public.room_game_sessions(room_id, solved_at) where status='solved';

create function public.control_chat_game(p_room text, p_action text, p_game text)
returns jsonb language plpgsql set search_path = public as $$
declare
  series chat_game_series;
  completed integer;
  outcome jsonb;
begin
  if p_action in ('start','change') then
    insert into chat_game_series(room_id,game_type,running)
    values(p_room,coalesce(p_game,'quiz'),false) on conflict do nothing;
  end if;
  select * into series from chat_game_series where room_id=p_room for update;
  if not found then return '{}'::jsonb; end if;
  update room_game_sessions set status='expired'
    where room_id=p_room and status='active' and expires_at<=clock_timestamp();
  if p_action='stop' then
    update room_game_sessions set status='cancelled' where room_id=p_room and status='active';
    update chat_game_series set running=false,generation=gen_random_uuid() where room_id=p_room;
    return jsonb_build_object('message','Game stopped.');
  end if;
  if p_action='change' or (p_action='start' and p_game is not null and p_game<>series.game_type) then
    select count(*) into completed from room_game_sessions where room_id=p_room
      and started_at>=series.since_at and status in ('solved','expired');
    if completed<5 then
      return jsonb_build_object('message',format('Finish %s more questions to change games.',5-completed));
    end if;
    if p_game is null or p_game=series.game_type then
      return jsonb_build_object('message','Choose a different game.');
    end if;
    update room_game_sessions set status='cancelled' where room_id=p_room and status='active';
    update chat_game_series set game_type=p_game,since_at=clock_timestamp(),generation=gen_random_uuid()
      where room_id=p_room returning * into series;
  end if;
  if p_action in ('start','change') then
    update chat_game_series set running=true where room_id=p_room returning * into series;
  end if;
  select jsonb_build_object('id',id,'at',coalesce(finished_at,solved_at,expires_at),'text',
    case when status='solved' then coalesce(winner_display_name,'Player')||' answered correctly! The answer is '
    else 'Nobody answered correctly. The answer was ' end ||secret_answer||'.')
    into outcome from room_game_sessions where room_id=p_room and status in ('solved','expired')
    order by started_at desc limit 1;
  return jsonb_build_object('running',series.running,'game_type',series.game_type,'generation',series.generation,'outcome',outcome);
end $$;

create function public.check_chat_game_generation() returns trigger language plpgsql set search_path=public as $$
begin
  if new.series_generation is not null then
    perform 1 from chat_game_series where room_id=new.room_id and running and generation=new.series_generation for update;
    if not found then raise exception 'Room game changed'; end if;
  end if;
  return new;
end $$;
create trigger check_game_generation before insert on public.room_game_sessions
for each row execute function public.check_chat_game_generation();

create function public.chat_game_period_results(p_room text)
returns table(period text, player text, wins bigint) language sql stable set search_path=public as $$
  with bounds(period,starts) as (values
    ('hour',date_trunc('hour',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
    ('day',date_trunc('day',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'))
  select b.period,r.player,r.wins from bounds b cross join lateral (
    select (array_agg(winner_display_name order by solved_at desc))[1] as player,count(*) as wins,min(solved_at) as first_win,winner_user_id
    from room_game_sessions where room_id=p_room and status='solved' and solved_at>=b.starts
    group by winner_user_id order by count(*) desc,min(solved_at),winner_user_id limit 3
  ) r order by b.period,r.wins desc,r.first_win,r.winner_user_id
$$;
revoke all on function public.control_chat_game(text,text,text), public.chat_game_period_results(text) from public,anon,authenticated;
grant execute on function public.control_chat_game(text,text,text), public.chat_game_period_results(text) to service_role;
