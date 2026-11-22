-- Spotmate Web: Scroll-Only YouTube Shorts Reels & Two-Way Private Chat Sharing
-- Migration 008 (run after 20261123000700_music_room_schema.sql)

create table if not exists public.spotmate_reels (
  id uuid primary key default gen_random_uuid(),
  youtube_video_id text not null unique,
  title text not null,
  creator_handle text not null default '@spotmate',
  city_tag text not null default 'Hyderabad',
  category text not null default 'trending' check (category in ('for_you', 'trending', 'city', 'food', 'travel', 'music')),
  thumbnail_url text generated always as ('https://i.ytimg.com/vi/' || youtube_video_id || '/hqdefault.jpg') stored,
  likes_count integer not null default 0 check (likes_count >= 0),
  shares_count integer not null default 0 check (shares_count >= 0),
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now()
);

create index if not exists idx_spotmate_reels_active_city
  on public.spotmate_reels (is_active, city_tag, sort_order, created_at desc);

create table if not exists public.spotmate_reel_likes (
  reel_id uuid not null references public.spotmate_reels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reel_id, user_id)
);

create table if not exists public.spotmate_reel_shares (
  id uuid primary key default gen_random_uuid(),
  reel_id uuid not null references public.spotmate_reels(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  chat_thread_id text,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists idx_spotmate_reel_shares_sender
  on public.spotmate_reel_shares (sender_id, created_at desc);

alter table public.spotmate_reels enable row level security;
alter table public.spotmate_reel_likes enable row level security;
alter table public.spotmate_reel_shares enable row level security;

drop policy if exists "Anyone authenticated can view active reels" on public.spotmate_reels;
create policy "Anyone authenticated can view active reels"
  on public.spotmate_reels for select
  using (is_active = true);

drop policy if exists "Users manage own reel likes" on public.spotmate_reel_likes;
create policy "Users manage own reel likes"
  on public.spotmate_reel_likes for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users view own sent or received reel shares" on public.spotmate_reel_shares;
create policy "Users view own sent or received reel shares"
  on public.spotmate_reel_shares for select
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

drop policy if exists "Users insert own reel shares" on public.spotmate_reel_shares;
create policy "Users insert own reel shares"
  on public.spotmate_reel_shares for insert
  with check (auth.uid() = sender_id);

-- Atomic like toggle RPC
create or replace function public.toggle_spotmate_reel_like(p_reel_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_exists boolean;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  perform 1 from public.spotmate_reels where id=p_reel_id and is_active for update;
  if not found then raise exception 'Reel unavailable'; end if;
  select exists(
    select 1 from public.spotmate_reel_likes
    where reel_id = p_reel_id and user_id = v_uid
  ) into v_exists;

  if v_exists then
    delete from public.spotmate_reel_likes
    where reel_id = p_reel_id and user_id = v_uid;
    update public.spotmate_reels
      set likes_count = greatest(likes_count - 1, 0)
      where id = p_reel_id
      returning likes_count into v_count;
    return jsonb_build_object('liked', false, 'likes_count', coalesce(v_count, 0));
  else
    insert into public.spotmate_reel_likes (reel_id, user_id)
    values (p_reel_id, v_uid)
    on conflict do nothing;
    update public.spotmate_reels
      set likes_count = likes_count + 1
      where id = p_reel_id
      returning likes_count into v_count;
    return jsonb_build_object('liked', true, 'likes_count', coalesce(v_count, 0));
  end if;
end;
$$;

-- Atomic share logging RPC returning canonical private-chat card payload
create or replace function public.record_spotmate_reel_share(
  p_reel_id uuid,
  p_recipient_id uuid,
  p_chat_thread_id text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_reel public.spotmate_reels%rowtype;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_reel from public.spotmate_reels where id = p_reel_id and is_active = true;
  if not found then
    raise exception 'Reel not found';
  end if;

  if not exists(select 1 from public.spotmate_direct_inbox() inbox where inbox.conversation_id::text=p_chat_thread_id and inbox.other_id=p_recipient_id) then
    raise exception 'Choose a connected chat';
  end if;
  insert into public.messages(conversation_id,sender_id,message)
    values(p_chat_thread_id::uuid,v_uid,'Reel · '||jsonb_build_object('type','shared_reel','reel_id',v_reel.id,'youtube_video_id',v_reel.youtube_video_id,'title',v_reel.title,'creator_handle',v_reel.creator_handle,'city_tag',v_reel.city_tag,'thumbnail_url',v_reel.thumbnail_url,'note',left(p_note,300))::text);
  insert into public.spotmate_reel_shares (reel_id, sender_id, recipient_id, chat_thread_id, note)
  values (p_reel_id, v_uid, p_recipient_id, p_chat_thread_id, p_note);

  update public.spotmate_reels
    set shares_count = shares_count + 1
    where id = p_reel_id;

  return jsonb_build_object(
    'type', 'shared_reel',
    'reel_id', v_reel.id,
    'youtube_video_id', v_reel.youtube_video_id,
    'title', v_reel.title,
    'creator_handle', v_reel.creator_handle,
    'city_tag', v_reel.city_tag,
    'thumbnail_url', v_reel.thumbnail_url,
    'note', p_note
  );
end;
$$;
