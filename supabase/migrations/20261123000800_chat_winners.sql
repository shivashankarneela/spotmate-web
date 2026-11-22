create extension if not exists pg_cron;
create table public.chat_game_announcements (
  room_id text not null,
  period text not null check(period in ('hour','day')),
  ends_at timestamptz not null,
  winners text[] not null,
  wins integer not null,
  primary key(room_id,period,ends_at)
);
alter table public.chat_game_announcements enable row level security;
create policy read_joined_game_results on public.chat_game_announcements for select to authenticated using
(exists(select 1 from public.hotspot_members m where m.hotspot_id::text=room_id and m.user_id=auth.uid() and m.status='active' and m.expires_at>now()));
create index if not exists game_win_times on public.room_game_sessions(solved_at) where status='solved';
create function public.publish_chat_game_results() returns void language sql security definer set search_path=public,pg_temp as $$
insert into public.chat_game_announcements(room_id,period,ends_at,winners,wins)
with totals as (
 select room_id,period,(date_trunc(period, solved_at at time zone 'Asia/Kolkata')+
 case period when 'hour' then interval '1 hour' else interval '1 day' end) at time zone 'Asia/Kolkata' ends_at,
 winner_user_id,(array_agg(coalesce(winner_display_name,'Player') order by solved_at desc,id))[1] player,count(*)::integer wins
 from public.room_game_sessions cross join (values ('hour'),('day')) periods(period)
 where status='solved' and solved_at>=now()-interval '3 days' and winner_user_id is not null
 group by 1,2,3,4
), ranked as (
 select *,dense_rank() over(partition by room_id,period,ends_at order by wins desc) place from totals
)
select room_id,period,ends_at,array_agg(player order by player,winner_user_id),max(wins)
from ranked where place=1 and ends_at<=now() and ends_at>now()-interval '2 days'
group by 1,2,3 on conflict do nothing
$$;
revoke all on function public.publish_chat_game_results() from public,anon,authenticated;
select cron.schedule('publish-chat-game-results','0,30 * * * *','select public.publish_chat_game_results()');
-- Functions that act on a supplied user ID are called only by the authenticated Edge Functions.
do $$ declare f regprocedure; begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname=any(array['claim_chat_game_win','pick_next_unseen_game_item','arena_lock_match_escrow','arena_settle_match','arena_update_chess_elo','music_create_custom_room','music_join_room_atomic','music_leave_and_reallocate'])
 loop execute format('revoke execute on function %s from public, anon, authenticated',f);
 execute format('grant execute on function %s to service_role',f); end loop;
end $$;
