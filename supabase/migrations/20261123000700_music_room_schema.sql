-- =============================================================================
-- Spotmate Web — 5-Member Video + Audio Music Room Schema & Atomic RPCs
-- Free Rooms: 0 SC, 30-min cap, max 5 members, auto-close when empty -> next 5-user batch
-- Custom Rooms: 5 SC (30 min) or 10 SC (60 min), max 5 members, Room Code + Spotmate ID invites
-- Playback: Host-only Groovy-style (!play, !pause, !resume, !skip, !queue, !np, !stop)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Music Rooms
CREATE TABLE IF NOT EXISTS public.music_rooms (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_code           TEXT UNIQUE NOT NULL,
  title               TEXT NOT NULL,
  mode                TEXT NOT NULL CHECK (mode IN ('free', 'custom')),
  duration_minutes    INTEGER NOT NULL CHECK (duration_minutes IN (30, 60)),
  cost_sc             INTEGER NOT NULL DEFAULT 0 CHECK (cost_sc >= 0),
  max_members         INTEGER NOT NULL DEFAULT 5 CHECK (max_members = 5),
  host_user_id        UUID NOT NULL,
  status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  -- Synced Video + Audio Playback Anchor
  current_source_type TEXT CHECK (current_source_type IN ('youtube', 'hls_audio')),
  current_source_ref  TEXT,       -- YouTube 11-char videoId OR HLS/MP3 audio stream URL
  current_title       TEXT,
  started_at          TIMESTAMPTZ,
  seek_offset_ms      INTEGER NOT NULL DEFAULT 0,
  is_playing          BOOLEAN NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at          TIMESTAMPTZ NOT NULL,
  closed_at           TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_music_rooms_active_mode
  ON public.music_rooms (mode, status, expires_at DESC)
  WHERE status = 'active';

-- 2. Room Members (Strictly capped at 5 per room)
CREATE TABLE IF NOT EXISTS public.music_room_members (
  room_id      UUID NOT NULL REFERENCES public.music_rooms(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL,
  display_name TEXT NOT NULL,
  avatar_url   TEXT,
  joined_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (room_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_music_room_members_room
  ON public.music_room_members (room_id, joined_at ASC);

-- 3. Track Queue (Host-managed via !play / !skip / !stop)
CREATE TABLE IF NOT EXISTS public.music_room_queue (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id     UUID NOT NULL REFERENCES public.music_rooms(id) ON DELETE CASCADE,
  added_by    UUID NOT NULL,
  source_type TEXT NOT NULL CHECK (source_type IN ('youtube', 'hls_audio')),
  source_ref  TEXT NOT NULL,
  title       TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'playing', 'played', 'skipped')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_music_room_queue_active
  ON public.music_room_queue (room_id, status, created_at ASC);

-- 4. Next-Batch Waitlist for Free 30-Min Rooms (allocates up to 5 users per fresh room)
CREATE TABLE IF NOT EXISTS public.music_room_waitlist (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL,
  display_name      TEXT NOT NULL,
  avatar_url        TEXT,
  status            TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'allocated', 'cancelled')),
  allocated_room_id UUID REFERENCES public.music_rooms(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_music_waitlist_user_waiting
  ON public.music_room_waitlist (user_id)
  WHERE status = 'waiting';

-- 5. Direct Custom Room Invites by Spotmate ID / User ID
CREATE TABLE IF NOT EXISTS public.music_room_invites (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id        UUID NOT NULL REFERENCES public.music_rooms(id) ON DELETE CASCADE,
  room_code      TEXT NOT NULL,
  room_title     TEXT NOT NULL,
  from_user_id   UUID NOT NULL,
  from_name      TEXT NOT NULL,
  to_user_id     UUID NOT NULL,
  to_spotmate_id TEXT NOT NULL,
  status         TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired')),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at     TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '5 minutes')
);

CREATE INDEX IF NOT EXISTS idx_music_invites_recipient
  ON public.music_room_invites (to_user_id, status, expires_at DESC);

-- 6. In-Room Live Chat + MusicBot Command Feed
CREATE TABLE IF NOT EXISTS public.music_room_messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id      UUID NOT NULL REFERENCES public.music_rooms(id) ON DELETE CASCADE,
  user_id      UUID,
  display_name TEXT NOT NULL,
  kind         TEXT NOT NULL DEFAULT 'chat' CHECK (kind IN ('chat', 'command', 'bot')),
  content      TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 300),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_music_room_messages_room
  ON public.music_room_messages (room_id, created_at DESC);

-- 7. Row Level Security
ALTER TABLE public.music_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.music_room_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.music_room_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.music_room_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.music_room_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.music_room_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "music_rooms_read_public_or_member" ON public.music_rooms;
CREATE POLICY "music_rooms_read_public_or_member"
  ON public.music_rooms FOR SELECT
  TO authenticated
  USING (
    mode = 'free'
    OR host_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.music_room_members m
      WHERE m.room_id = music_rooms.id AND m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "music_members_read_all" ON public.music_room_members;
CREATE POLICY "music_members_read_all"
  ON public.music_room_members FOR SELECT
  TO authenticated
  USING (TRUE);

DROP POLICY IF EXISTS "music_queue_read_members" ON public.music_room_queue;
CREATE POLICY "music_queue_read_members"
  ON public.music_room_queue FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.music_room_members m
      WHERE m.room_id = music_room_queue.room_id AND m.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "music_waitlist_read_own" ON public.music_room_waitlist;
CREATE POLICY "music_waitlist_read_own"
  ON public.music_room_waitlist FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "music_invites_read_involved" ON public.music_room_invites;
CREATE POLICY "music_invites_read_involved"
  ON public.music_room_invites FOR SELECT
  TO authenticated
  USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

DROP POLICY IF EXISTS "music_messages_read_members" ON public.music_room_messages;
CREATE POLICY "music_messages_read_members"
  ON public.music_room_messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.music_room_members m
      WHERE m.room_id = music_room_messages.room_id AND m.user_id = auth.uid()
    )
  );

-- 8. Helper: Generate unique SPOT-XXXX room code
CREATE OR REPLACE FUNCTION public.generate_music_room_code()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code  TEXT;
  i       INTEGER;
BEGIN
  LOOP
    v_code := 'SPOT-';
    FOR i IN 1..4 LOOP
      v_code := v_code || substr(v_chars, 1 + floor(random() * length(v_chars))::INT, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.music_rooms WHERE room_code = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;

-- 9. Atomic RPC: Create Custom Room (30m = 5 SC, 60m = 10 SC)
CREATE OR REPLACE FUNCTION public.music_create_custom_room(
  p_host_id          UUID,
  p_host_name        TEXT,
  p_host_avatar_url  TEXT,
  p_title            TEXT,
  p_duration_minutes INTEGER -- 30 (5 SC) or 60 (10 SC)
)
RETURNS public.music_rooms
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cost    INTEGER;
  v_code    TEXT;
  v_room    public.music_rooms;
  v_updated INTEGER;
BEGIN
  IF p_duration_minutes = 30 THEN
    v_cost := 5;
  ELSIF p_duration_minutes = 60 THEN
    v_cost := 10;
  ELSE
    RAISE EXCEPTION 'Custom rooms support 30 mins (5 SC) or 60 mins (10 SC).';
  END IF;

  UPDATE public.wallets SET balance=balance-v_cost WHERE user_id=p_host_id AND balance>=v_cost;
  IF NOT FOUND THEN RAISE EXCEPTION 'INSUFFICIENT_SC_BALANCE'; END IF;
  v_code := public.generate_music_room_code();

  INSERT INTO public.music_rooms (
    room_code, title, mode, duration_minutes, cost_sc, max_members, host_user_id, expires_at
  )
  VALUES (
    v_code,
    COALESCE(NULLIF(trim(p_title), ''), p_host_name || '''s Music Room'),
    'custom',
    p_duration_minutes,
    v_cost,
    5,
    p_host_id,
    NOW() + make_interval(mins => p_duration_minutes)
  )
  RETURNING * INTO v_room;

  INSERT INTO public.music_room_members (room_id, user_id, display_name, avatar_url)
  VALUES (v_room.id, p_host_id, p_host_name, p_host_avatar_url);

  INSERT INTO public.music_room_messages (room_id, display_name, kind, content)
  VALUES (
    v_room.id,
    'MusicBot',
    'bot',
    'Custom room created (' || p_duration_minutes || 'm • ' || v_cost || ' SC). Share code ' || v_code || ' or type !play <song> to start!'
  );

  RETURN v_room;
END;
$$;

-- 10. Atomic RPC: Join Room (Strictly enforces 5-member capacity & active timer)
CREATE OR REPLACE FUNCTION public.music_join_room_atomic(
  p_room_id      UUID,
  p_user_id      UUID,
  p_display_name TEXT,
  p_avatar_url   TEXT DEFAULT NULL
)
RETURNS public.music_rooms
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room  public.music_rooms;
  v_count INTEGER;
BEGIN
  SELECT * INTO v_room
    FROM public.music_rooms
   WHERE id = p_room_id
   FOR UPDATE;

  IF v_room.id IS NULL OR v_room.status <> 'active' OR v_room.expires_at <= NOW() THEN
    RAISE EXCEPTION 'ROOM_CLOSED_OR_EXPIRED';
  END IF;

  -- Already a member -> allow seamless reconnect
  IF EXISTS (SELECT 1 FROM public.music_room_members WHERE room_id = p_room_id AND user_id = p_user_id) THEN
    RETURN v_room;
  END IF;

  SELECT count(*) INTO v_count FROM public.music_room_members WHERE room_id = p_room_id;
  IF v_count >= v_room.max_members THEN
    RAISE EXCEPTION 'ROOM_FULL';
  END IF;

  INSERT INTO public.music_room_members (room_id, user_id, display_name, avatar_url)
  VALUES (p_room_id, p_user_id, p_display_name, p_avatar_url);

  RETURN v_room;
END;
$$;

-- 11. Atomic RPC: Leave Room -> Auto-transfer Host OR Close Empty Room & Allocate Next 5-User Batch
CREATE OR REPLACE FUNCTION public.music_leave_and_reallocate(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room          public.music_rooms;
  v_remaining     INTEGER;
  v_next_host     public.music_room_members;
  v_new_room      public.music_rooms;
  v_batch_count   INTEGER;
  v_first_waiter  public.music_room_waitlist;
BEGIN
  SELECT * INTO v_room FROM public.music_rooms WHERE id = p_room_id FOR UPDATE;
  IF v_room.id IS NULL THEN
    RETURN jsonb_build_object('closed', true);
  END IF;

  DELETE FROM public.music_room_members
   WHERE room_id = p_room_id AND user_id = p_user_id;

  SELECT count(*) INTO v_remaining FROM public.music_room_members WHERE room_id = p_room_id;

  -- Empty room -> close immediately and allocate a fresh 30-min Free room to next waiting batch (up to 5)
  IF v_remaining = 0 THEN
    UPDATE public.music_rooms
       SET status = 'closed', is_playing = FALSE, closed_at = NOW()
     WHERE id = p_room_id;

    IF v_room.mode = 'free' THEN
      SELECT count(*) INTO v_batch_count
        FROM public.music_room_waitlist
       WHERE status = 'waiting';

      IF v_batch_count > 0 THEN
        SELECT * INTO v_first_waiter
          FROM public.music_room_waitlist
         WHERE status = 'waiting'
         ORDER BY created_at ASC
         LIMIT 1;

        INSERT INTO public.music_rooms (
          room_code, title, mode, duration_minutes, cost_sc, max_members, host_user_id, expires_at
        )
        VALUES (
          public.generate_music_room_code(),
          v_room.title,
          'free',
          30,
          0,
          5,
          v_first_waiter.user_id,
          NOW() + INTERVAL '30 minutes'
        )
        RETURNING * INTO v_new_room;

        -- Seat up to 5 waiting users into the newly allocated Free room
        WITH batch AS (
          SELECT id, user_id, display_name, avatar_url
            FROM public.music_room_waitlist
           WHERE status = 'waiting'
           ORDER BY created_at ASC
           LIMIT 5
           FOR UPDATE SKIP LOCKED
        ),
        mark_wait AS (
          UPDATE public.music_room_waitlist w
             SET status = 'allocated', allocated_room_id = v_new_room.id
            FROM batch b
           WHERE w.id = b.id
          RETURNING b.user_id, b.display_name, b.avatar_url
        )
        INSERT INTO public.music_room_members (room_id, user_id, display_name, avatar_url)
        SELECT v_new_room.id, user_id, display_name, avatar_url FROM mark_wait;

        RETURN jsonb_build_object('closed', true, 'reallocated_room_id', v_new_room.id);
      END IF;
    END IF;

    RETURN jsonb_build_object('closed', true);
  END IF;

  -- If Host left a Free room while others remain -> auto-transfer Host to longest-standing member
  IF v_room.host_user_id = p_user_id AND v_room.mode = 'free' THEN
    SELECT * INTO v_next_host
      FROM public.music_room_members
     WHERE room_id = p_room_id
     ORDER BY joined_at ASC
     LIMIT 1;

    IF v_next_host.user_id IS NOT NULL THEN
      UPDATE public.music_rooms
         SET host_user_id = v_next_host.user_id
       WHERE id = p_room_id;

      INSERT INTO public.music_room_messages (room_id, display_name, kind, content)
      VALUES (
        p_room_id,
        'MusicBot',
        'bot',
        v_next_host.display_name || ' is now the Room Host! Use !play <song> to control music.'
      );
    END IF;
  END IF;

  RETURN jsonb_build_object('closed', false, 'remaining_members', v_remaining);
END;
$$;
