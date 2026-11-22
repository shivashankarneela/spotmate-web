import { ArenaGameReducer, ArenaPlayerMeta, ReducerResult } from "./types.ts";

/**
 * Snakes & Ladders (2 to 4 players)
 * - 10x10 board (tiles 1..100).
 * - 14 snakes (including high-drama 99->78, 95->75, 92->73, 87->24).
 * - 6 ladders — NONE of which reach tile 100 (highest ladder tops out at 91).
 * - Exact-100 finish rule; rolling a 6 grants an extra turn (capped at 2 consecutive 6s).
 */

export const SNAKES_MAP: Record<number, number> = {
  99: 78,
  95: 75,
  92: 73,
  87: 24,
  74: 53,
  64: 60,
  62: 19,
  54: 34,
  49: 11,
  17: 7,
  28: 9,
  39: 21,
  68: 47,
  83: 57,
};

export const LADDERS_MAP: Record<number, number> = {
  4: 25,
  13: 46,
  33: 49,
  42: 63,
  50: 69,
  71: 91,
};

export interface SnakesMoveLog {
  user_id: string;
  display_name: string;
  dice: number;
  from: number;
  landed: number;
  final_tile: number;
  event: "normal" | "ladder" | "snake" | "overshoot" | "win";
  extra_turn: boolean;
}

export interface SnakesLaddersState {
  positions: Record<string, number>;
  turn_index: number;
  consecutive_sixes: number;
  last_dice: number | null;
  last_move: SnakesMoveLog | null;
  snakes: Record<number, number>;
  ladders: Record<number, number>;
  standings: string[]; // ordered user_ids when game finishes
}

const TURN_SECONDS = 15;

function rollServerDie(): number {
  const arr = new Uint32Array(1);
  crypto.getRandomValues(arr);
  return (arr[0] % 6) + 1;
}

export const snakesLaddersReducer: ArenaGameReducer = {
  gameType: "snakes_ladders",

  initState(players: ArenaPlayerMeta[]) {
    if (players.length < 2 || players.length > 4) {
      throw new Error("Snakes & Ladders supports 2 to 4 players.");
    }
    const positions: Record<string, number> = {};
    for (const p of players) {
      positions[p.user_id] = 0; // off-board start; first roll moves onto 1..6
    }

    const state: SnakesLaddersState = {
      positions,
      turn_index: 0,
      consecutive_sixes: 0,
      last_dice: null,
      last_move: null,
      snakes: SNAKES_MAP,
      ladders: LADDERS_MAP,
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
    const state: SnakesLaddersState = structuredClone(
      rawState as unknown as SnakesLaddersState,
    );

    const currentPlayer = players[state.turn_index];
    if (!currentPlayer || currentPlayer.user_id !== actorUserId) {
      throw new Error("It is not your turn to roll.");
    }
    if (payload.type !== "roll") {
      throw new Error("Unsupported action. Expected { type: 'roll' }.");
    }

    const dice = rollServerDie();
    const from = state.positions[actorUserId] ?? 0;
    let landed = from + dice;
    let finalTile = landed;
    let event: SnakesMoveLog["event"] = "normal";

    if (landed > 100) {
      // Exact-100 finish required
      landed = from;
      finalTile = from;
      event = "overshoot";
    } else if (state.snakes[landed] !== undefined) {
      finalTile = state.snakes[landed];
      event = "snake";
    } else if (LADDERS_MAP[landed] !== undefined) {
      finalTile = LADDERS_MAP[landed];
      event = "ladder";
    }

    state.positions[actorUserId] = finalTile;
    state.last_dice = dice;

    // Check victory
    if (finalTile === 100) {
      event = "win";
      state.last_move = {
        user_id: actorUserId,
        display_name: currentPlayer.display_name,
        dice,
        from,
        landed,
        final_tile: 100,
        event,
        extra_turn: false,
      };

      // Rank all players by descending tile position
      state.standings = [...players]
        .sort((a, b) => (state.positions[b.user_id] ?? 0) - (state.positions[a.user_id] ?? 0))
        .map((p) => p.user_id);

      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: null,
        turnSeconds: 0,
        finished: true,
        finalStatus: "completed",
        winnerUserId: actorUserId,
        winReason: `${currentPlayer.display_name} reached tile 100!`,
      };
    }

    // Extra turn on rolling a 6 (up to 2 consecutive 6s)
    const earnedExtraTurn = dice === 6 && state.consecutive_sixes < 2;
    if (earnedExtraTurn) {
      state.consecutive_sixes += 1;
    } else {
      state.consecutive_sixes = 0;
      state.turn_index = (state.turn_index + 1) % players.length;
    }

    state.last_move = {
      user_id: actorUserId,
      display_name: currentPlayer.display_name,
      dice,
      from,
      landed,
      final_tile: finalTile,
      event,
      extra_turn: earnedExtraTurn,
    };

    const nextPlayer = players[state.turn_index];
    return {
      nextState: state as unknown as Record<string, unknown>,
      turnUserId: nextPlayer.user_id,
      turnSeconds: TURN_SECONDS,
      finished: false,
    };
  },

  sanitizeForPlayer(rawState: Record<string, unknown>, _viewerUserId: string) {
    // Snakes & Ladders has no hidden state
    return rawState;
  },
};
