export type ArenaGameType = "hand_cricket" | "snakes_ladders" | "ludo" | "chess" | "carrom";

export interface ArenaPlayerMeta {
  user_id: string;
  display_name: string;
  avatar_url?: string | null;
}

export interface ReducerResult {
  nextState: Record<string, unknown>;
  turnUserId: string | null;
  turnSeconds: number;
  finished: boolean;
  finalStatus?: "completed" | "draw";
  winnerUserId?: string | null;
  winReason?: string;
}

export interface ArenaGameReducer {
  gameType: ArenaGameType;
  initState(players: ArenaPlayerMeta[]): {
    state: Record<string, unknown>;
    turnUserId: string | null;
    turnSeconds: number;
  };
  applyAction(
    state: Record<string, unknown>,
    players: ArenaPlayerMeta[],
    actorUserId: string,
    payload: Record<string, unknown>,
  ): ReducerResult;
  /**
   * Removes secret/unrevealed fields before sending state to a specific player.
   * Critical for Hand Cricket commit-reveal fairness.
   */
  sanitizeForPlayer(
    state: Record<string, unknown>,
    viewerUserId: string,
  ): Record<string, unknown>;
}
