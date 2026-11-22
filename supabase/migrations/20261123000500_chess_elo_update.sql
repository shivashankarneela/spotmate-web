-- =============================================================================
-- Spotmate Web — Games Arena Phase 4 Migration (Chess ELO Rating RPC)
-- Requires: Phase 1 migration (001_games_arena_escrow_schema.sql)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.arena_update_chess_elo(
  p_white_id UUID,
  p_black_id UUID,
  p_outcome  TEXT -- 'white' | 'black' | 'draw'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_white_elo INTEGER := 1200;
  v_black_elo INTEGER := 1200;
  v_expected_white DOUBLE PRECISION;
  v_score_white    DOUBLE PRECISION;
  v_k              CONSTANT DOUBLE PRECISION := 32.0;
  v_white_delta    INTEGER;
  v_black_delta    INTEGER;
  v_white_new      INTEGER;
  v_black_new      INTEGER;
BEGIN
  -- Ensure both players have a chess stats row
  INSERT INTO public.arena_player_stats (user_id, game_type, elo_rating)
  VALUES (p_white_id, 'chess', 1200), (p_black_id, 'chess', 1200)
  ON CONFLICT (user_id, game_type) DO NOTHING;

  SELECT elo_rating INTO v_white_elo
    FROM public.arena_player_stats
   WHERE user_id = p_white_id AND game_type = 'chess';

  SELECT elo_rating INTO v_black_elo
    FROM public.arena_player_stats
   WHERE user_id = p_black_id AND game_type = 'chess';

  v_expected_white := 1.0 / (1.0 + power(10.0, (v_black_elo - v_white_elo) / 400.0));

  IF p_outcome = 'white' THEN
    v_score_white := 1.0;
  ELSIF p_outcome = 'black' THEN
    v_score_white := 0.0;
  ELSE
    v_score_white := 0.5;
  END IF;

  v_white_delta := round(v_k * (v_score_white - v_expected_white))::INTEGER;
  v_black_delta := -v_white_delta;

  v_white_new := GREATEST(100, v_white_elo + v_white_delta);
  v_black_new := GREATEST(100, v_black_elo + v_black_delta);

  UPDATE public.arena_player_stats
     SET elo_rating = v_white_new, updated_at = NOW()
   WHERE user_id = p_white_id AND game_type = 'chess';

  UPDATE public.arena_player_stats
     SET elo_rating = v_black_new, updated_at = NOW()
   WHERE user_id = p_black_id AND game_type = 'chess';

  RETURN jsonb_build_object(
    'white_old', v_white_elo,
    'white_new', v_white_new,
    'white_delta', v_white_new - v_white_elo,
    'black_old', v_black_elo,
    'black_new', v_black_new,
    'black_delta', v_black_new - v_black_elo
  );
END;
$$;
