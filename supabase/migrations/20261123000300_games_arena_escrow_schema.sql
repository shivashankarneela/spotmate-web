-- =============================================================================
-- Spotmate Web — Games Arena Phase 1 Schema, Matchmaking & Atomic SC Escrow
-- Supports: hand_cricket, snakes_ladders, ludo, chess
-- Modes: Free (stake_sc = 0) and SC Wager (stake_sc > 0)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Random Matchmaking Queue
CREATE TABLE IF NOT EXISTS public.arena_matchmaking_queue (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL,
  display_name  TEXT NOT NULL,
  avatar_url    TEXT,
  game_type     TEXT NOT NULL CHECK (game_type IN ('hand_cricket', 'snakes_ladders', 'ludo', 'chess')),
  player_count  INTEGER NOT NULL DEFAULT 2 CHECK (player_count BETWEEN 2 AND 4),
  stake_sc      INTEGER NOT NULL DEFAULT 0 CHECK (stake_sc >= 0),
  status        TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'matched', 'cancelled', 'expired')),
  matched_id    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at    TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '90 seconds')
);

CREATE INDEX IF NOT EXISTS idx_arena_queue_lookup
  ON public.arena_matchmaking_queue (game_type, player_count, stake_sc, status, created_at)
  WHERE status = 'waiting';

-- One active waiting queue entry per user at a time
CREATE UNIQUE INDEX IF NOT EXISTS uq_arena_queue_user_waiting
  ON public.arena_matchmaking_queue (user_id)
  WHERE status = 'waiting';

-- 2. Direct Challenges by Spotmate ID
CREATE TABLE IF NOT EXISTS public.arena_game_challenges (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id     UUID NOT NULL,
  from_name        TEXT NOT NULL,
  from_avatar_url  TEXT,
  to_user_id       UUID NOT NULL,
  to_spotmate_id   TEXT NOT NULL,
  game_type        TEXT NOT NULL CHECK (game_type IN ('hand_cricket', 'snakes_ladders', 'ludo', 'chess')),
  stake_sc         INTEGER NOT NULL DEFAULT 0 CHECK (stake_sc >= 0),
  status           TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  match_id         UUID,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at       TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '60 seconds')
);

CREATE INDEX IF NOT EXISTS idx_arena_challenges_recipient
  ON public.arena_game_challenges (to_user_id, status, expires_at DESC);

-- 3. Unified Multiplayer Matches
CREATE TABLE IF NOT EXISTS public.arena_game_matches (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_type           TEXT NOT NULL CHECK (game_type IN ('hand_cricket', 'snakes_ladders', 'ludo', 'chess')),
  source_mode         TEXT NOT NULL CHECK (source_mode IN ('random_queue', 'spotmate_id')),
  stake_sc            INTEGER NOT NULL DEFAULT 0 CHECK (stake_sc >= 0),
  pot_sc              INTEGER NOT NULL DEFAULT 0 CHECK (pot_sc >= 0),
  player_ids          UUID[] NOT NULL,
  players_meta        JSONB NOT NULL DEFAULT '[]'::jsonb,
  state_json          JSONB NOT NULL DEFAULT '{}'::jsonb,
  turn_user_id        UUID,
  turn_expires_at     TIMESTAMPTZ NOT NULL,
  status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'draw', 'forfeit', 'cancelled')),
  winner_user_id      UUID,
  win_reason          TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at         TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_arena_matches_status
  ON public.arena_game_matches (status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_arena_matches_players
  ON public.arena_game_matches USING GIN (player_ids);

-- 4. Immutable SC Escrow Ledger
CREATE TABLE IF NOT EXISTS public.arena_escrow_ledger (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id    UUID NOT NULL REFERENCES public.arena_game_matches(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL,
  amount_sc   INTEGER NOT NULL,
  entry_type  TEXT NOT NULL CHECK (entry_type IN ('lock', 'payout', 'refund')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_arena_escrow_match
  ON public.arena_escrow_ledger (match_id, user_id);

-- Prevent duplicate lock/payout/refund for same (match, user, entry_type)
CREATE UNIQUE INDEX IF NOT EXISTS uq_arena_escrow_idempotent
  ON public.arena_escrow_ledger (match_id, user_id, entry_type);

-- 5. Per-Game Player Stats & ELO
CREATE TABLE IF NOT EXISTS public.arena_player_stats (
  user_id         UUID NOT NULL,
  game_type       TEXT NOT NULL CHECK (game_type IN ('hand_cricket', 'snakes_ladders', 'ludo', 'chess')),
  wins            INTEGER NOT NULL DEFAULT 0,
  losses          INTEGER NOT NULL DEFAULT 0,
  draws           INTEGER NOT NULL DEFAULT 0,
  current_streak  INTEGER NOT NULL DEFAULT 0,
  best_streak     INTEGER NOT NULL DEFAULT 0,
  net_sc          INTEGER NOT NULL DEFAULT 0,
  elo_rating      INTEGER NOT NULL DEFAULT 1200,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, game_type)
);

-- 6. Row Level Security
ALTER TABLE public.arena_matchmaking_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arena_game_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arena_game_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arena_escrow_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.arena_player_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "queue_read_own" ON public.arena_matchmaking_queue;
CREATE POLICY "queue_read_own"
  ON public.arena_matchmaking_queue FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "challenges_read_involved" ON public.arena_game_challenges;
CREATE POLICY "challenges_read_involved"
  ON public.arena_game_challenges FOR SELECT
  TO authenticated
  USING (auth.uid() = from_user_id OR auth.uid() = to_user_id);

DROP POLICY IF EXISTS "escrow_read_own" ON public.arena_escrow_ledger;
CREATE POLICY "escrow_read_own"
  ON public.arena_escrow_ledger FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "stats_read_all" ON public.arena_player_stats;
CREATE POLICY "stats_read_all"
  ON public.arena_player_stats FOR SELECT
  TO authenticated, anon
  USING (TRUE);

-- Note: arena_game_matches raw rows are NOT directly readable by clients so hidden state
-- (such as Hand Cricket pending picks) is never exposed. Clients fetch sanitized state
-- from the `arena-match-engine` Edge Function and subscribe to Realtime broadcasts.

-- 7. Atomic SC Escrow Lock RPC (called by Edge Function with service_role)
CREATE OR REPLACE FUNCTION public.arena_lock_match_escrow(
  p_match_id   UUID,
  p_player_ids UUID[],
  p_stake_sc   INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_uid UUID;
  v_updated INTEGER;
BEGIN
  -- Free Mode (0 SC): no wallet debit required
  IF p_stake_sc <= 0 THEN
    RETURN TRUE;
  END IF;

  FOREACH v_uid IN ARRAY p_player_ids LOOP
    INSERT INTO public.arena_escrow_ledger (match_id, user_id, amount_sc, entry_type)
    VALUES (p_match_id, v_uid, -p_stake_sc, 'lock')
    ON CONFLICT (match_id, user_id, entry_type) DO NOTHING;
    IF FOUND THEN
      UPDATE public.wallets SET balance=balance-p_stake_sc WHERE user_id=v_uid AND balance>=p_stake_sc;
      IF NOT FOUND THEN RAISE EXCEPTION 'INSUFFICIENT_SC_BALANCE'; END IF;
    END IF;
  END LOOP;

  RETURN TRUE;
END;
$$;

-- 8. Atomic Settlement RPC (Win Payout / Forfeit Payout / Draw Refund)
CREATE OR REPLACE FUNCTION public.arena_settle_match(
  p_match_id       UUID,
  p_final_status   TEXT,      -- 'completed' | 'forfeit' | 'draw'
  p_winner_user_id UUID,      -- NULL on draw
  p_win_reason     TEXT,
  p_final_state    JSONB
)
RETURNS TABLE (
  settled    BOOLEAN,
  pot_sc     INTEGER,
  winner_id  UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_match public.arena_game_matches;
  v_uid   UUID;
BEGIN
  UPDATE public.arena_game_matches
     SET status         = p_final_status,
         winner_user_id = p_winner_user_id,
         win_reason     = p_win_reason,
         state_json     = COALESCE(p_final_state, state_json),
         updated_at     = NOW(),
         finished_at    = NOW()
   WHERE id = p_match_id
     AND status = 'active'
  RETURNING * INTO v_match;

  IF v_match.id IS NULL THEN
    RETURN QUERY SELECT FALSE, 0, NULL::UUID;
    RETURN;
  END IF;

  -- Settle SC Escrow if wagered match
  IF v_match.stake_sc > 0 THEN
    IF p_final_status = 'draw' OR p_winner_user_id IS NULL THEN
      FOREACH v_uid IN ARRAY v_match.player_ids LOOP
        INSERT INTO public.arena_escrow_ledger (match_id, user_id, amount_sc, entry_type)
        VALUES (v_match.id, v_uid, v_match.stake_sc, 'refund')
        ON CONFLICT (match_id, user_id, entry_type) DO NOTHING;
        -- SPOTMATE WALLET REFUND HOOK:
        UPDATE public.wallets SET balance = balance + v_match.stake_sc WHERE user_id = v_uid;
      END LOOP;
    ELSE
      INSERT INTO public.arena_escrow_ledger (match_id, user_id, amount_sc, entry_type)
      VALUES (v_match.id, p_winner_user_id, v_match.pot_sc, 'payout')
      ON CONFLICT (match_id, user_id, entry_type) DO NOTHING;
      -- SPOTMATE WALLET PAYOUT HOOK:
      UPDATE public.wallets SET balance = balance + v_match.pot_sc WHERE user_id = p_winner_user_id;
    END IF;
  END IF;

  -- Update player stats
  FOREACH v_uid IN ARRAY v_match.player_ids LOOP
    IF p_final_status = 'draw' OR p_winner_user_id IS NULL THEN
      INSERT INTO public.arena_player_stats (user_id, game_type, draws, updated_at)
      VALUES (v_uid, v_match.game_type, 1, NOW())
      ON CONFLICT (user_id, game_type) DO UPDATE SET
        draws = public.arena_player_stats.draws + 1,
        updated_at = NOW();
    ELSIF v_uid = p_winner_user_id THEN
      INSERT INTO public.arena_player_stats (user_id, game_type, wins, current_streak, best_streak, net_sc, updated_at)
      VALUES (v_uid, v_match.game_type, 1, 1, 1, (v_match.pot_sc - v_match.stake_sc), NOW())
      ON CONFLICT (user_id, game_type) DO UPDATE SET
        wins = public.arena_player_stats.wins + 1,
        current_streak = public.arena_player_stats.current_streak + 1,
        best_streak = GREATEST(public.arena_player_stats.best_streak, public.arena_player_stats.current_streak + 1),
        net_sc = public.arena_player_stats.net_sc + (v_match.pot_sc - v_match.stake_sc),
        updated_at = NOW();
    ELSE
      INSERT INTO public.arena_player_stats (user_id, game_type, losses, current_streak, net_sc, updated_at)
      VALUES (v_uid, v_match.game_type, 1, 0, -v_match.stake_sc, NOW())
      ON CONFLICT (user_id, game_type) DO UPDATE SET
        losses = public.arena_player_stats.losses + 1,
        current_streak = 0,
        net_sc = public.arena_player_stats.net_sc - v_match.stake_sc,
        updated_at = NOW();
    END IF;
  END LOOP;

  RETURN QUERY SELECT TRUE, v_match.pot_sc, p_winner_user_id;
END;
$$;
