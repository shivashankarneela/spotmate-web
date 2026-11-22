import { ArenaGameReducer, ArenaPlayerMeta, ReducerResult } from "./types.ts";

/**
 * Hand Cricket: Super Over (1v1, 6 balls per innings, 1 wicket)
 * - Simultaneous commit-reveal per ball: both players submit 1..6.
 * - Server hides each player's pending pick from the opponent until both lock in.
 * - Equal numbers => OUT (innings ends immediately).
 * - Otherwise => batter's pick is added to the innings score.
 */

export interface BallLog {
  innings: 1 | 2;
  ball: number;
  batter_id: string;
  bowler_id: string;
  batter_pick: number;
  bowler_pick: number;
  is_out: boolean;
  runs: number;
}

export interface HandCricketState {
  innings: 1 | 2;
  ball: number; // 1..6
  max_balls: number;
  batter_id: string;
  bowler_id: string;
  scores: Record<string, number>;
  wickets: Record<string, number>;
  target: number | null;
  pending_picks: Record<string, number>; // SECRET until both players commit
  last_ball: BallLog | null;
  history: BallLog[];
}

const BALL_TURN_SECONDS = 12;

export const handCricketReducer: ArenaGameReducer = {
  gameType: "hand_cricket",

  initState(players: ArenaPlayerMeta[]) {
    if (players.length !== 2) {
      throw new Error("Hand Cricket requires exactly 2 players.");
    }
    const [p1, p2] = players;
    const state: HandCricketState = {
      innings: 1,
      ball: 1,
      max_balls: 6,
      batter_id: p1.user_id,
      bowler_id: p2.user_id,
      scores: { [p1.user_id]: 0, [p2.user_id]: 0 },
      wickets: { [p1.user_id]: 0, [p2.user_id]: 0 },
      target: null,
      pending_picks: {},
      last_ball: null,
      history: [],
    };
    return {
      state: state as unknown as Record<string, unknown>,
      turnUserId: null, // simultaneous commit by both players
      turnSeconds: BALL_TURN_SECONDS,
    };
  },

  applyAction(
    rawState: Record<string, unknown>,
    players: ArenaPlayerMeta[],
    actorUserId: string,
    payload: Record<string, unknown>,
  ): ReducerResult {
    const state: HandCricketState = structuredClone(rawState as unknown as HandCricketState);
    const pick = Number(payload.pick);

    if (!Number.isInteger(pick) || pick < 1 || pick > 6) {
      throw new Error("Pick must be an integer between 1 and 6.");
    }
    if (actorUserId !== state.batter_id && actorUserId !== state.bowler_id) {
      throw new Error("Only match participants can submit a pick.");
    }
    if (state.pending_picks[actorUserId] !== undefined) {
      throw new Error("You have already locked your pick for this ball.");
    }

    state.pending_picks[actorUserId] = pick;

    const batterPick = state.pending_picks[state.batter_id];
    const bowlerPick = state.pending_picks[state.bowler_id];

    // Wait for the other player to lock in
    if (batterPick === undefined || bowlerPick === undefined) {
      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: batterPick === undefined ? state.batter_id : state.bowler_id,
        turnSeconds: BALL_TURN_SECONDS,
        finished: false,
      };
    }

    // Both players committed -> resolve the ball!
    const isOut = batterPick === bowlerPick;
    const runs = isOut ? 0 : batterPick;

    if (isOut) {
      state.wickets[state.batter_id] = (state.wickets[state.batter_id] ?? 0) + 1;
    } else {
      state.scores[state.batter_id] = (state.scores[state.batter_id] ?? 0) + runs;
    }

    const ballLog: BallLog = {
      innings: state.innings,
      ball: state.ball,
      batter_id: state.batter_id,
      bowler_id: state.bowler_id,
      batter_pick: batterPick,
      bowler_pick: bowlerPick,
      is_out: isOut,
      runs,
    };
    state.last_ball = ballLog;
    state.history.push(ballLog);
    state.pending_picks = {};

    const batterScore = state.scores[state.batter_id];
    const inningsOver = isOut || state.ball >= state.max_balls;

    // Innings 1 logic
    if (state.innings === 1) {
      if (inningsOver) {
        state.target = batterScore + 1;
        state.innings = 2;
        state.ball = 1;
        // Swap batter and bowler
        const prevBatter = state.batter_id;
        state.batter_id = state.bowler_id;
        state.bowler_id = prevBatter;
      } else {
        state.ball += 1;
      }

      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: null,
        turnSeconds: BALL_TURN_SECONDS,
        finished: false,
      };
    }

    // Innings 2 chase logic
    const target = state.target ?? 1;
    if (batterScore >= target) {
      const winnerName =
        players.find((p) => p.user_id === state.batter_id)?.display_name ?? "Batter";
      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: null,
        turnSeconds: 0,
        finished: true,
        finalStatus: "completed",
        winnerUserId: state.batter_id,
        winReason: `${winnerName} chased down ${target} runs!`,
      };
    }

    if (inningsOver) {
      const firstScore = state.scores[state.bowler_id];
      if (batterScore === firstScore) {
        return {
          nextState: state as unknown as Record<string, unknown>,
          turnUserId: null,
          turnSeconds: 0,
          finished: true,
          finalStatus: "draw",
          winnerUserId: null,
          winReason: `Match tied at ${batterScore} runs each!`,
        };
      }
      const winnerName =
        players.find((p) => p.user_id === state.bowler_id)?.display_name ?? "Bowler";
      const margin = firstScore - batterScore;
      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: null,
        turnSeconds: 0,
        finished: true,
        finalStatus: "completed",
        winnerUserId: state.bowler_id,
        winReason: `${winnerName} defended the total by ${margin} run${margin === 1 ? "" : "s"}!`,
      };
    }

    state.ball += 1;
    return {
      nextState: state as unknown as Record<string, unknown>,
      turnUserId: null,
      turnSeconds: BALL_TURN_SECONDS,
      finished: false,
    };
  },

  sanitizeForPlayer(rawState: Record<string, unknown>, viewerUserId: string) {
    const state = rawState as unknown as HandCricketState;
    const pending = state.pending_picks ?? {};
    return {
      innings: state.innings,
      ball: state.ball,
      max_balls: state.max_balls,
      batter_id: state.batter_id,
      bowler_id: state.bowler_id,
      scores: state.scores,
      wickets: state.wickets,
      target: state.target,
      // Reveal ONLY whether each player has locked in, plus the viewer's own pick
      locked_players: Object.keys(pending),
      my_pick: pending[viewerUserId] ?? null,
      last_ball: state.last_ball,
      history: state.history,
    };
  },
};
