-- =============================================================================
-- Spotmate Web — Games Arena Phase 5 Migration (Enable 'carrom' game_type)
-- Requires: Phase 1 migration (001_games_arena_escrow_schema.sql)
-- =============================================================================

ALTER TABLE public.arena_matchmaking_queue
  DROP CONSTRAINT IF EXISTS arena_matchmaking_queue_game_type_check;
ALTER TABLE public.arena_matchmaking_queue
  ADD CONSTRAINT arena_matchmaking_queue_game_type_check
  CHECK (game_type IN ('hand_cricket', 'snakes_ladders', 'ludo', 'chess', 'carrom'));

ALTER TABLE public.arena_game_challenges
  DROP CONSTRAINT IF EXISTS arena_game_challenges_game_type_check;
ALTER TABLE public.arena_game_challenges
  ADD CONSTRAINT arena_game_challenges_game_type_check
  CHECK (game_type IN ('hand_cricket', 'snakes_ladders', 'ludo', 'chess', 'carrom'));

ALTER TABLE public.arena_game_matches
  DROP CONSTRAINT IF EXISTS arena_game_matches_game_type_check;
ALTER TABLE public.arena_game_matches
  ADD CONSTRAINT arena_game_matches_game_type_check
  CHECK (game_type IN ('hand_cricket', 'snakes_ladders', 'ludo', 'chess', 'carrom'));

ALTER TABLE public.arena_player_stats
  DROP CONSTRAINT IF EXISTS arena_player_stats_game_type_check;
ALTER TABLE public.arena_player_stats
  ADD CONSTRAINT arena_player_stats_game_type_check
  CHECK (game_type IN ('hand_cricket', 'snakes_ladders', 'ludo', 'chess', 'carrom'));
