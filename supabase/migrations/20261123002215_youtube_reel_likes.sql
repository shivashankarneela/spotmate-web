create table if not exists public.youtube_reel_likes (
 video_id text not null check (video_id ~ '^[A-Za-z0-9_-]{11}$'),
 user_id uuid not null references auth.users(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(video_id,user_id)
);
alter table public.youtube_reel_likes enable row level security;
revoke all on public.youtube_reel_likes from public, anon, authenticated;
create or replace function public.youtube_reel_like_states(p_video_ids text[])
returns table(video_id text, liked boolean, likes_count bigint)
language sql stable security definer set search_path = '' as $$
 select l.video_id, bool_or(l.user_id = (select auth.uid())), count(*)
 from public.youtube_reel_likes l
 where (select auth.uid()) is not null and l.video_id = any(coalesce(p_video_ids, array[]::text[]))
 group by l.video_id
$$;
create or replace function public.toggle_youtube_reel_like(p_video_id text,p_title text,p_creator text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); was_liked boolean; total bigint;
begin
 if uid is null then raise exception 'Sign in required'; end if;
 if p_video_id is null or p_video_id !~ '^[A-Za-z0-9_-]{11}$' then raise exception 'Invalid video'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(uid::text || ':' || p_video_id,0));
 delete from public.youtube_reel_likes where video_id=p_video_id and user_id=uid;
 was_liked := found;
 if not was_liked then
  insert into public.youtube_reel_likes(video_id,user_id) values(p_video_id,uid);
 end if;
 select count(*) into total from public.youtube_reel_likes where video_id=p_video_id;
 return pg_catalog.jsonb_build_object('liked',not was_liked,'likes_count',total);
end $$;
revoke all on function public.youtube_reel_like_states(text[]) from public, anon;
revoke all on function public.toggle_youtube_reel_like(text,text,text) from public, anon;
grant execute on function public.youtube_reel_like_states(text[]) to authenticated;
grant execute on function public.toggle_youtube_reel_like(text,text,text) to authenticated;