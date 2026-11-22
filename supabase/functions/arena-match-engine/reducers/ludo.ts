import { ArenaGameReducer, ArenaPlayerMeta, ReducerResult } from "./types.ts";

/**
 * Classic Ludo (2 to 4 players)
 * - Outer track: 52 squares (0..51).
 * - Per-token relative progress:
 *     -1     = In home yard (needs a 6 to enter at relative step 0)
 *     0..50  = On the 52-square outer track (global index = (seatStart + step) % 52)
 *     51..55 = Inside player's private 5-square colored home column (safe)
 *     56     = Finished in central home triangle!
 * - 8 Star Safe Squares on outer track: 0, 8, 13, 21, 26, 34, 39, 47.
 * - Capturing an opponent on a non-safe outer tile sends them to -1 and grants a bonus roll.
 * - Rolling a 6 grants a bonus roll (3 consecutive 6s forfeits turn).
 */

export const LUDO_SAFE_TILES = new Set<number>([0, 8, 13, 21, 26, 34, 39, 47]);
const TURN_SECONDS = 20;

export interface LudoMoveLog {
  user_id: string;
  display_name: string;
  dice: number;
  token_index: number | null;
  from_step: number | null;
  to_step: number | null;
  captured_user_id: string | null;
  event: "rolled" | "entered" | "moved" | "captured" | "home" | "no_moves" | "triple_six" | "win";
  extra_turn: boolean;
}

export interface LudoState {
  /** Maps user_id -> seat start offset on 52-square track (0, 13, 26, or 39) */
  seat_starts: Record<string, number>;
  /** Maps user_id -> [t0, t1, t2, t3], each in -1..56 */
  tokens: Record<string, number[]>;
  turn_index: number;
  phase: "await_roll" | "await_token";
  dice_value: number | null;
  legal_tokens: number[];
  consecutive_sixes: number;
  last_move: LudoMoveLog | null;
  standings: string[];
}

function rollServerDie(): number {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  return (arr[0] % 6) + 1;
}

function seatOffsetsForCount(count: number): number[] {
  // 2 players sit diagonally opposite (0 and 26); 3-4 players sit clockwise
  if (count === 2) return [0, 26];
  if (count === 3) return [0, 13, 26];
  return [0, 13, 26, 39];
}

function computeLegalTokens(playerTokens: number[], dice: number): number[] {
  const legal: number[] = [];
  for (let i = 0; i < 4; i++) {
    const pos = playerTokens[i];
    if (pos === -1) {
      if (dice === 6) legal.push(i);
    } else if (pos < 56 && pos + dice <= 56) {
      legal.push(i);
    }
  }
  return legal;
}

function globalTile(seatStart: number, relativeStep: number): number | null {
  if (relativeStep < 0 || relativeStep > 50) return null;
  return (seatStart + relativeStep) % 52;
}

export const ludoReducer: ArenaGameReducer = {
  gameType: "ludo",

  initState(players: ArenaPlayerMeta[]) {
    if (players.length < 2 || players.length > 4) {
      throw new Error("Ludo supports 2 to 4 players.");
    }
    const offsets = seatOffsetsForCount(players.length);
    const seatStarts: Record<string, number> = {};
    const tokens: Record<string, number[]> = {};

    players.forEach((p, idx) => {
      seatStarts[p.user_id] = offsets[idx];
      tokens[p.user_id] = [-1, -1, -1, -1];
    });

    const state: LudoState = {
      seat_starts: seatStarts,
      tokens,
      turn_index: 0,
      phase: "await_roll",
      dice_value: null,
      legal_tokens: [],
      consecutive_sixes: 0,
      last_move: null,
      standings: [],
    };

    return {
      state: state as unknown as Record<string, unknown>,
      turnUserId: players[0].user_id,
      turnSeconds: TURN_SECONDS,
    };
  },

  applyAction(
    rawState: Record<string, unknown>,
    players: ArenaPlayerMeta[],
    actorUserId: string,
    payload: Record<string, unknown>,
  ): ReducerResult {
    const state: LudoState = structuredClone(rawState as unknown as LudoState);
    const currentPlayer = players[state.turn_index];

    if (!currentPlayer || currentPlayer.user_id !== actorUserId) {
      throw new Error("It is not your turn.");
    }

    const actionType = String(payload.type ?? "");

    // -------------------------------------------------------------------------
    // STEP 1: ROLL DICE
    // -------------------------------------------------------------------------
    if (actionType === "roll") {
      if (state.phase !== "await_roll") {
        throw new Error("Select a token to move before rolling again.");
      }

      const dice = rollServerDie();
      state.dice_value = dice;

      // Triple-6 forfeit rule
      if (dice === 6 && state.consecutive_sixes >= 2) {
        state.consecutive_sixes = 0;
        state.legal_tokens = [];
        state.phase = "await_roll";
        state.turn_index = (state.turn_index + 1) % players.length;
        state.last_move = {
          user_id: actorUserId,
          display_name: currentPlayer.display_name,
          dice,
          token_index: null,
          from_step: null,
          to_step: null,
          captured_user_id: null,
          event: "triple_six",
          extra_turn: false,
        };
        return {
          nextState: state as unknown as Record<string, unknown>,
          turnUserId: players[state.turn_index].user_id,
          turnSeconds: TURN_SECONDS,
          finished: false,
        };
      }

      const legal = computeLegalTokens(state.tokens[actorUserId], dice);

      if (legal.length === 0) {
        state.consecutive_sixes = 0;
        state.legal_tokens = [];
        state.phase = "await_roll";
        state.turn_index = (state.turn_index + 1) % players.length;
        state.last_move = {
          user_id: actorUserId,
          display_name: currentPlayer.display_name,
          dice,
          token_index: null,
          from_step: null,
          to_step: null,
          captured_user_id: null,
          event: "no_moves",
          extra_turn: false,
        };
        return {
          nextState: state as unknown as Record<string, unknown>,
          turnUserId: players[state.turn_index].user_id,
          turnSeconds: TURN_SECONDS,
          finished: false,
        };
      }

      // If only 1 token is legal, auto-move it immediately for snappy UX
      if (legal.length === 1) {
        state.phase = "await_token";
        state.legal_tokens = legal;
        return executeTokenMove(state, players, currentPlayer, legal[0]);
      }

      state.phase = "await_token";
      state.legal_tokens = legal;
      state.last_move = {
        user_id: actorUserId,
        display_name: currentPlayer.display_name,
        dice,
        token_index: null,
        from_step: null,
        to_step: null,
        captured_user_id: null,
        event: "rolled",
        extra_turn: false,
      };

      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: actorUserId,
        turnSeconds: TURN_SECONDS,
        finished: false,
      };
    }

    // -------------------------------------------------------------------------
    // STEP 2: MOVE SELECTED TOKEN
    // -------------------------------------------------------------------------
    if (actionType === "move_token") {
      if (state.phase !== "await_token" || state.dice_value === null) {
        throw new Error("Roll the dice first.");
      }
      const tokenIndex = Number(payload.token_index);
      if (!state.legal_tokens.includes(tokenIndex)) {
        throw new Error("That token cannot legally move.");
      }
      return executeTokenMove(state, players, currentPlayer, tokenIndex);
    }

    throw new Error("Expected action type 'roll' or 'move_token'.");
  },

  sanitizeForPlayer(rawState: Record<string, unknown>, _viewerUserId: string) {
    return rawState;
  },
};

function executeTokenMove(
  state: LudoState,
  players: ArenaPlayerMeta[],
  currentPlayer: ArenaPlayerMeta,
  tokenIndex: number,
): ReducerResult {
  const actorId = currentPlayer.user_id;
  const dice = state.dice_value!;
  const myTokens = state.tokens[actorId];
  const fromStep = myTokens[tokenIndex];
  const toStep = fromStep === -1 ? 0 : fromStep + dice;
  myTokens[tokenIndex] = toStep;

  let event: LudoMoveLog["event"] = fromStep === -1 ? "entered" : "moved";
  let capturedUserId: string | null = null;

  // Check capture on non-safe outer track squares
  const landedGlobal = globalTile(state.seat_starts[actorId], toStep);
  if (landedGlobal !== null && !LUDO_SAFE_TILES.has(landedGlobal)) {
    for (const opp of players) {
      if (opp.user_id === actorId) continue;
      const oppTokens = state.tokens[opp.user_id];
      for (let j = 0; j < 4; j++) {
        const oppGlobal = globalTile(state.seat_starts[opp.user_id], oppTokens[j]);
        if (oppGlobal === landedGlobal) {
          oppTokens[j] = -1; // send back to home yard
          capturedUserId = opp.user_id;
          event = "captured";
        }
      }
    }
  }

  if (toStep === 56) {
    event = "home";
  }

  // Check victory: all 4 tokens at step 56
  const allHome = myTokens.every((t) => t === 56);
  if (allHome) {
    state.phase = "await_roll";
    state.legal_tokens = [];
    state.standings = [...players]
      .sort((a, b) => {
        const scoreA = state.tokens[a.user_id].reduce((acc, v) => acc + (v < 0 ? 0 : v + 1), 0);
        const scoreB = state.tokens[b.user_id].reduce((acc, v) => acc + (v < 0 ? 0 : v + 1), 0);
        return scoreB - scoreA;
      })
      .map((p) => p.user_id);

    state.last_move = {
      user_id: actorId,
      display_name: currentPlayer.display_name,
      dice,
      token_index: tokenIndex,
      from_step: fromStep,
      to_step: toStep,
      captured_user_id: capturedUserId,
      event: "win",
      extra_turn: false,
    };

    return {
      nextState: state as unknown as Record<string, unknown>,
      turnUserId: null,
      turnSeconds: 0,
      finished: true,
      finalStatus: "completed",
      winnerUserId: actorId,
      winReason: `${currentPlayer.display_name} brought all 4 tokens home!`,
    };
  }

  // Bonus turn on rolling a 6, capturing an opponent, or reaching home (56)
  const bonusTurn = dice === 6 || capturedUserId !== null || toStep === 56;
  if (bonusTurn) {
    state.consecutive_sixes = dice === 6 ? state.consecutive_sixes + 1 : 0;
  } else {
    state.consecutive_sixes = 0;
    state.turn_index = (state.turn_index + 1) % players.length;
  }

  state.phase = "await_roll";
  state.legal_tokens = [];
  state.last_move = {
    user_id: actorId,
    display_name: currentPlayer.display_name,
    dice,
    token_index: tokenIndex,
    from_step: fromStep,
    to_step: toStep,
    captured_user_id: capturedUserId,
    event,
    extra_turn: bonusTurn,
  };

  return {
    nextState: state as unknown as Record<string, unknown>,
    turnUserId: players[state.turn_index].user_id,
    turnSeconds: TURN_SECONDS,
    finished: false,
  };
}
