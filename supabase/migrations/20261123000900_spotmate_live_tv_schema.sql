-- Spotmate Web: Live TV (YouTube Live + HLS) with Watch-Together Chat & Private Chat Sharing
-- Migration 009 (run after 20261123000800_spotmate_reels_schema.sql)

create table if not exists public.spotmate_live_channels (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null default 'News' check (category in ('News', 'Sports', 'Music', 'Movies', 'Devotional', 'City Live')),
  language text not null default 'Telugu',
  stream_type text not null default 'youtube_live' check (stream_type in ('youtube_live', 'youtube_channel', 'hls')),
  stream_source text not null,
  logo_url text,
  is_live boolean not null default true,
  viewer_count integer not null default 0 check (viewer_count >= 0),
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);

create index if not exists idx_spotmate_live_channels_active
  on public.spotmate_live_channels (is_live, category, sort_order);

create table if not exists public.spotmate_live_tv_viewers (
  channel_id uuid not null references public.spotmate_live_channels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  primary key (channel_id, user_id)
);

create table if not exists public.spotmate_live_tv_messages (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.spotmate_live_channels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_url text,
  body text,
  reaction_emoji text,
  created_at timestamptz not null default now()
);

create index if not exists idx_spotmate_live_tv_messages_channel
  on public.spotmate_live_tv_messages (channel_id, created_at desc);

alter table public.spotmate_live_channels enable row level security;
alter table public.spotmate_live_tv_viewers enable row level security;
alter table public.spotmate_live_tv_messages enable row level security;

drop policy if exists "Authenticated users can view live channels" on public.spotmate_live_channels;
create policy "Authenticated users can view live channels"
  on public.spotmate_live_channels for select
  using (is_live = true);

drop policy if exists "Authenticated users can read live tv chat" on public.spotmate_live_tv_messages;
create policy "Authenticated users can read live tv chat"
  on public.spotmate_live_tv_messages for select
  using (auth.uid() is not null);

drop policy if exists "Authenticated users can send live tv chat" on public.spotmate_live_tv_messages;
create policy "Authenticated users can send live tv chat"
  on public.spotmate_live_tv_messages for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users manage own viewer heartbeat" on public.spotmate_live_tv_viewers;
create policy "Users manage own viewer heartbeat"
  on public.spotmate_live_tv_viewers for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Heartbeat RPC to keep live viewer count fresh (active in last 90 seconds)
create or replace function public.ping_live_tv_viewer(p_channel_id uuid)
returns integer
language plpgsql
security definer
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.spotmate_live_tv_viewers (channel_id, user_id, last_seen_at)
  values (p_channel_id, v_uid, now())
  on conflict (channel_id, user_id) do update set last_seen_at = now();

  delete from public.spotmate_live_tv_viewers
  where channel_id = p_channel_id
    and last_seen_at < now() - interval '90 seconds';

  select count(*)::integer into v_count
  from public.spotmate_live_tv_viewers
  where channel_id = p_channel_id;

  update public.spotmate_live_channels
    set viewer_count = v_count
    where id = p_channel_id;

  return v_count;
end;
$$;

-- Enable Supabase Realtime for live Watch-Together chat
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'spotmate_live_tv_messages'
  ) then
    alter publication supabase_realtime add table public.spotmate_live_tv_messages;
  end if;
end $$;
