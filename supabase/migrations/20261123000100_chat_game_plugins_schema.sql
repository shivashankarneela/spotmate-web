-- =============================================================================
-- Spotmate Web — Chat Game Plugins Schema, Anti-Repetition Engine & Atomic RPCs
-- Supports: quiz, anagram, five_letter, hangman, arithmetic_blitz
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Curated Content Bank (server-side only; hidden from direct client SELECT)
CREATE TABLE IF NOT EXISTS public.chat_game_items (
  id                TEXT PRIMARY KEY,
  game_type         TEXT NOT NULL CHECK (game_type IN ('quiz', 'anagram', 'five_letter', 'hangman')),
  category          TEXT NOT NULL,
  difficulty        TEXT NOT NULL CHECK (difficulty IN ('easy', 'medium', 'hard')),
  prompt_payload    JSONB NOT NULL,
  answer_normalized TEXT NOT NULL,
  accepted_aliases  JSONB NOT NULL DEFAULT '[]'::jsonb,
  sc_reward         INTEGER NOT NULL DEFAULT 10 CHECK (sc_reward > 0),
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_game_items_type_active
  ON public.chat_game_items (game_type, is_active);

-- 2. Per-Room Anti-Repetition Deck Tracker
--    An item cannot repeat in a room until the entire pool for that game_type is exhausted.
CREATE TABLE IF NOT EXISTS public.room_seen_game_items (
  room_id   TEXT NOT NULL,
  game_type TEXT NOT NULL,
  item_id   TEXT NOT NULL,
  seen_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (room_id, game_type, item_id)
);

CREATE INDEX IF NOT EXISTS idx_room_seen_lookup
  ON public.room_seen_game_items (room_id, game_type, seen_at DESC);

-- 3. Active & Historical Room Game Sessions
CREATE TABLE IF NOT EXISTS public.room_game_sessions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id             TEXT NOT NULL,
  game_type           TEXT NOT NULL CHECK (
                        game_type IN ('quiz', 'anagram', 'five_letter', 'hangman', 'arithmetic_blitz')
                      ),
  item_id             TEXT,
  category            TEXT NOT NULL,
  difficulty          TEXT NOT NULL DEFAULT 'medium',
  public_state        JSONB NOT NULL DEFAULT '{}'::jsonb,
  secret_answer       TEXT NOT NULL,
  accepted_aliases    JSONB NOT NULL DEFAULT '[]'::jsonb,
  hint_step           INTEGER NOT NULL DEFAULT 0,
  status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'solved', 'expired', 'cancelled')),
  started_by          UUID,
  winner_user_id      UUID,
  winner_display_name TEXT,
  sc_reward           INTEGER NOT NULL DEFAULT 10,
  started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at          TIMESTAMPTZ NOT NULL,
  solved_at           TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_room_game_sessions_room_status
  ON public.room_game_sessions (room_id, status, started_at DESC);

-- Prevent two active games simultaneously in the same chat room
CREATE UNIQUE INDEX IF NOT EXISTS uq_one_active_game_per_room
  ON public.room_game_sessions (room_id)
  WHERE (status = 'active');

-- 4. Room & Global Leaderboard
CREATE TABLE IF NOT EXISTS public.chat_game_leaderboard (
  room_id          TEXT NOT NULL,
  user_id          UUID NOT NULL,
  display_name     TEXT NOT NULL,
  wins             INTEGER NOT NULL DEFAULT 0,
  current_streak   INTEGER NOT NULL DEFAULT 0,
  best_streak      INTEGER NOT NULL DEFAULT 0,
  total_sc_earned  INTEGER NOT NULL DEFAULT 0,
  last_win_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (room_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_game_leaderboard_room_wins
  ON public.chat_game_leaderboard (room_id, wins DESC, total_sc_earned DESC);

-- 5. Safe Public View (NEVER exposes secret_answer or accepted_aliases to browsers)
CREATE OR REPLACE VIEW public.room_game_sessions_public AS
SELECT
  id,
  room_id,
  game_type,
  item_id,
  category,
  difficulty,
  public_state,
  hint_step,
  status,
  started_by,
  winner_user_id,
  winner_display_name,
  sc_reward,
  started_at,
  expires_at,
  solved_at,
  CASE WHEN status IN ('solved', 'expired') THEN secret_answer ELSE NULL END AS revealed_answer
FROM public.room_game_sessions;

-- 6. Row Level Security
ALTER TABLE public.chat_game_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_seen_game_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.room_game_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_game_leaderboard ENABLE ROW LEVEL SECURITY;

-- Clients cannot read raw chat_game_items or secret_answer directly (service_role bypasses RLS)
DROP POLICY IF EXISTS "leaderboard_read_all" ON public.chat_game_leaderboard;
CREATE POLICY "leaderboard_read_all"
  ON public.chat_game_leaderboard FOR SELECT
  TO authenticated, anon
  USING (TRUE);

-- Allow authenticated clients to read ONLY sanitized rows via security_invoker view or RPC
GRANT SELECT ON public.room_game_sessions_public TO authenticated, anon;
GRANT SELECT ON public.chat_game_leaderboard TO authenticated, anon;

-- 7. Anti-Repetition Deck Picker RPC (called by Edge Function with service_role)
CREATE OR REPLACE FUNCTION public.pick_next_unseen_game_item(
  p_room_id   TEXT,
  p_game_type TEXT
)
RETURNS public.chat_game_items
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_item public.chat_game_items;
BEGIN
  -- Pick a random unseen item for this room + game_type
  SELECT i.*
    INTO v_item
  FROM public.chat_game_items i
  WHERE i.game_type = p_game_type
    AND i.is_active = TRUE
    AND NOT EXISTS (
      SELECT 1
      FROM public.room_seen_game_items s
      WHERE s.room_id = p_room_id
        AND s.game_type = p_game_type
        AND s.item_id = i.id
    )
  ORDER BY random()
  LIMIT 1;

  -- If the entire 500+ pool has been cycled in this room, reset the room deck and draw fresh
  IF v_item.id IS NULL THEN
    DELETE FROM public.room_seen_game_items
    WHERE room_id = p_room_id
      AND game_type = p_game_type;

    SELECT i.*
      INTO v_item
    FROM public.chat_game_items i
    WHERE i.game_type = p_game_type
      AND i.is_active = TRUE
    ORDER BY random()
    LIMIT 1;
  END IF;

  IF v_item.id IS NOT NULL THEN
    INSERT INTO public.room_seen_game_items (room_id, game_type, item_id)
    VALUES (p_room_id, p_game_type, v_item.id)
    ON CONFLICT (room_id, game_type, item_id) DO UPDATE SET seen_at = NOW();
  END IF;

  RETURN v_item;
END;
$$;

-- 8. Atomic Win Claim & SC Reward RPC (prevents race conditions on simultaneous replies)
CREATE OR REPLACE FUNCTION public.claim_chat_game_win(
  p_session_id          UUID,
  p_winner_user_id      UUID,
  p_winner_display_name TEXT,
  p_public_state_patch  JSONB DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  claimed     BOOLEAN,
  sc_awarded  INTEGER,
  room_id     TEXT,
  game_type   TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_session public.room_game_sessions;
BEGIN
  -- Atomic lock + state transition: only the first caller wins
  UPDATE public.room_game_sessions
  SET
    status              = 'solved',
    winner_user_id      = p_winner_user_id,
    winner_display_name = p_winner_display_name,
    solved_at           = NOW(),
    public_state        = public_state || COALESCE(p_public_state_patch, '{}'::jsonb)
  WHERE id = p_session_id
    AND status = 'active'
    AND expires_at > NOW()
  RETURNING * INTO v_session;

  IF v_session.id IS NULL THEN
    RETURN QUERY SELECT FALSE, 0, NULL::TEXT, NULL::TEXT;
    RETURN;
  END IF;

  -- Upsert room leaderboard
  INSERT INTO public.chat_game_leaderboard (
    room_id, user_id, display_name, wins, current_streak, best_streak, total_sc_earned, last_win_at
  )
  VALUES (
    v_session.room_id, p_winner_user_id, p_winner_display_name, 1, 1, 1, v_session.sc_reward, NOW()
  )
  ON CONFLICT ON CONSTRAINT chat_game_leaderboard_pkey DO UPDATE SET
    display_name    = EXCLUDED.display_name,
    wins            = public.chat_game_leaderboard.wins + 1,
    current_streak  = public.chat_game_leaderboard.current_streak + 1,
    best_streak     = GREATEST(public.chat_game_leaderboard.best_streak, public.chat_game_leaderboard.current_streak + 1),
    total_sc_earned = public.chat_game_leaderboard.total_sc_earned + v_session.sc_reward,
    last_win_at     = NOW();

  -- ---------------------------------------------------------------------------
  UPDATE public.wallets SET balance=balance+v_session.sc_reward WHERE user_id=p_winner_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Wallet unavailable'; END IF;
  RETURN QUERY SELECT TRUE, v_session.sc_reward, v_session.room_id, v_session.game_type;
END;
$$;
