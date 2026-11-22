-- =============================================================================
-- Spotmate Web — Games Arena Phase 2 Migration
-- Adds in-game text chat & emoji reactions table for live matches (2–4 players)
-- Requires: Phase 1 migration (001_games_arena_escrow_schema.sql)
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.arena_match_messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id     UUID NOT NULL REFERENCES public.arena_game_matches(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL,
  display_name TEXT NOT NULL,
  kind         TEXT NOT NULL DEFAULT 'text' CHECK (kind IN ('text', 'emoji')),
  content      TEXT NOT NULL CHECK (char_length(content) BETWEEN 1 AND 180),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_arena_match_messages_match
  ON public.arena_match_messages (match_id, created_at DESC);

ALTER TABLE public.arena_match_messages ENABLE ROW LEVEL SECURITY;

-- Only participants in the match can read or post in-game messages/emojis
DROP POLICY IF EXISTS "match_chat_read_participants" ON public.arena_match_messages;
CREATE POLICY "match_chat_read_participants"
  ON public.arena_match_messages FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.arena_game_matches m
      WHERE m.id = arena_match_messages.match_id
        AND auth.uid() = ANY(m.player_ids)
    )
  );

DROP POLICY IF EXISTS "match_chat_insert_participants" ON public.arena_match_messages;
CREATE POLICY "match_chat_insert_participants"
  ON public.arena_match_messages FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.arena_game_matches m
      WHERE m.id = arena_match_messages.match_id
        AND auth.uid() = ANY(m.player_ids)
    )
  );
