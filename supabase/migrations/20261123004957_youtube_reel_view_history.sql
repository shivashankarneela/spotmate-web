create table public.youtube_reel_views (
  user_id uuid not null references auth.users(id) on delete cascade,
  video_id text not null check (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  viewed_at timestamptz not null default now(),
  primary key (user_id, video_id)
);
alter table public.youtube_reel_views enable row level security;
grant select, insert, update on public.youtube_reel_views to authenticated;
create policy "Users read their own reel views" on public.youtube_reel_views for select to authenticated using ((select auth.uid()) = user_id);
create policy "Users add their own reel views" on public.youtube_reel_views for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "Users update their own reel views" on public.youtube_reel_views for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create index youtube_reel_views_recent_idx on public.youtube_reel_views(user_id, viewed_at desc);