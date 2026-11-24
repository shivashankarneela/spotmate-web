alter table public.room_game_sessions alter column sc_reward set default 0;
update public.room_game_sessions set sc_reward = 0
where status = 'active' and sc_reward <> 0;

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
SET search_path = ''
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
    sc_reward           = 0,
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
    v_session.room_id, p_winner_user_id, p_winner_display_name, 1, 1, 1, 0, NOW()
  )
  ON CONFLICT ON CONSTRAINT chat_game_leaderboard_pkey DO UPDATE SET
    display_name    = EXCLUDED.display_name,
    wins            = public.chat_game_leaderboard.wins + 1,
    current_streak  = public.chat_game_leaderboard.current_streak + 1,
    best_streak     = GREATEST(public.chat_game_leaderboard.best_streak, public.chat_game_leaderboard.current_streak + 1),
    last_win_at     = NOW();

  RETURN QUERY SELECT TRUE, 0, v_session.room_id, v_session.game_type;
END;
$$;

revoke execute on function public.claim_chat_game_win(uuid, uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.claim_chat_game_win(uuid, uuid, text, jsonb)
  to service_role;
