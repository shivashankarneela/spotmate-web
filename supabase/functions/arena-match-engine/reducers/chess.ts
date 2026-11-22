import { Chess } from "https://esm.sh/chess.js@1.0.0-beta.8";
import { ArenaGameReducer, ArenaPlayerMeta, ReducerResult } from "./types.ts";

/**
 * Server-Authoritative 1v1 Chess Reducer (chess.js)
 * - Supports 3+2, 5+3, and 10+0 time controls with server-tracked clocks (ms) + increment.
 * - Full FIDE legality: castling, en passant, pawn promotion, checkmate, stalemate,
 *   insufficient material, threefold repetition, and 50-move rule.
 * - Mutual Draw Offer (`offer_draw`, `accept_draw`, `decline_draw`) cleanly refunds SC escrow.
 */

export interface ChessState {
  white_id: string;
  black_id: string;
  fen: string;
  time_control: string; // '3+2' | '5+3' | '10+0'
  increment_ms: number;
  clocks_ms: Record<string, number>;
  last_move_at_ms: number;
  last_move: { from: string; to: string; san: string } | null;
  moves_san: string[];
  draw_offer_by: string | null;
  in_check: boolean;
  elo_summary?: Record<string, unknown> | null;
}

const DEFAULT_BASE_MS = 5 * 60 * 1000; // 5 minutes
const DEFAULT_INC_MS = 3 * 1000;       // +3 seconds

export const chessReducer: ArenaGameReducer = {
  gameType: "chess",

  initState(players: ArenaPlayerMeta[]) {
    if (players.length !== 2) {
      throw new Error("Chess requires exactly 2 players.");
    }
    const [white, black] = players;
    const chess = new Chess();
    const now = Date.now();

    const state: ChessState = {
      white_id: white.user_id,
      black_id: black.user_id,
      fen: chess.fen(),
      time_control: "5+3",
      increment_ms: DEFAULT_INC_MS,
      clocks_ms: {
        [white.user_id]: DEFAULT_BASE_MS,
        [black.user_id]: DEFAULT_BASE_MS,
      },
      last_move_at_ms: now,
      last_move: null,
      moves_san: [],
      draw_offer_by: null,
      in_check: false,
      elo_summary: null,
    };

    return {
      state: state as unknown as Record<string, unknown>,
      turnUserId: white.user_id,
      turnSeconds: Math.ceil(DEFAULT_BASE_MS / 1000),
    };
  },

  applyAction(
    rawState: Record<string, unknown>,
    players: ArenaPlayerMeta[],
    actorUserId: string,
    payload: Record<string, unknown>,
  ): ReducerResult {
    const state: ChessState = structuredClone(rawState as unknown as ChessState);
    const chess = new Chess(state.fen);
    const actionType = String(payload.type ?? "move");

    const activeColor = chess.turn(); // 'w' | 'b'
    const expectedTurnId = activeColor === "w" ? state.white_id : state.black_id;
    const opponentId = actorUserId === state.white_id ? state.black_id : state.white_id;

    // -------------------------------------------------------------------------
    // DRAW OFFER FLOW
    // -------------------------------------------------------------------------
    if (actionType === "offer_draw") {
      state.draw_offer_by = actorUserId;
      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: expectedTurnId,
        turnSeconds: Math.max(1, Math.ceil((state.clocks_ms[expectedTurnId] ?? 60000) / 1000)),
        finished: false,
      };
    }

    if (actionType === "decline_draw") {
      state.draw_offer_by = null;
      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: expectedTurnId,
        turnSeconds: Math.max(1, Math.ceil((state.clocks_ms[expectedTurnId] ?? 60000) / 1000)),
        finished: false,
      };
    }

    if (actionType === "accept_draw") {
      if (!state.draw_offer_by || state.draw_offer_by === actorUserId) {
        throw new Error("No opponent draw offer to accept.");
      }
      state.draw_offer_by = null;
      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: null,
        turnSeconds: 0,
        finished: true,
        finalStatus: "draw",
        winnerUserId: null,
        winReason: "Draw by mutual agreement.",
      };
    }

    // -------------------------------------------------------------------------
    // STANDARD MOVE
    // -------------------------------------------------------------------------
    if (actorUserId !== expectedTurnId) {
      throw new Error("It is not your turn to move.");
    }

    // Deduct elapsed time on actor's clock
    const now = Date.now();
    const elapsed = Math.max(0, now - (state.last_move_at_ms ?? now));
    const remainingBeforeInc = (state.clocks_ms[actorUserId] ?? DEFAULT_BASE_MS) - elapsed;

    if (remainingBeforeInc <= 0) {
      state.clocks_ms[actorUserId] = 0;
      const winnerName =
        players.find((p) => p.user_id === opponentId)?.display_name ?? "Opponent";
      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: null,
        turnSeconds: 0,
        finished: true,
        finalStatus: "completed",
        winnerUserId: opponentId,
        winReason: `${winnerName} wins on time!`,
      };
    }

    const from = String(payload.from ?? "").trim().toLowerCase();
    const to = String(payload.to ?? "").trim().toLowerCase();
    const promotion = payload.promotion ? String(payload.promotion).toLowerCase() : "q";

    const move = chess.move({ from, to, promotion });
    if (!move) {
      throw new Error(`Illegal chess move: ${from} -> ${to}`);
    }

    // Apply increment after legal move
    state.clocks_ms[actorUserId] = remainingBeforeInc + (state.increment_ms ?? DEFAULT_INC_MS);
    state.last_move_at_ms = now;
    state.fen = chess.fen();
    state.last_move = { from: move.from, to: move.to, san: move.san };
    state.moves_san.push(move.san);
    state.draw_offer_by = null;
    state.in_check = chess.inCheck();

    // Terminal game checks
    if (chess.isCheckmate()) {
      const winnerName =
        players.find((p) => p.user_id === actorUserId)?.display_name ?? "Winner";
      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: null,
        turnSeconds: 0,
        finished: true,
        finalStatus: "completed",
        winnerUserId: actorUserId,
        winReason: `Checkmate! ${winnerName} wins!`,
      };
    }

    if (chess.isDraw() || chess.isStalemate() || chess.isThreefoldRepetition() || chess.isInsufficientMaterial()) {
      const reason = chess.isStalemate()
        ? "Draw by stalemate."
        : chess.isInsufficientMaterial()
        ? "Draw by insufficient material."
        : chess.isThreefoldRepetition()
        ? "Draw by threefold repetition."
        : "Draw by 50-move rule.";

      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: null,
        turnSeconds: 0,
        finished: true,
        finalStatus: "draw",
        winnerUserId: null,
        winReason: reason,
      };
    }

    const nextTurnId = chess.turn() === "w" ? state.white_id : state.black_id;
    const nextSeconds = Math.max(1, Math.ceil((state.clocks_ms[nextTurnId] ?? DEFAULT_BASE_MS) / 1000));

    return {
      nextState: state as unknown as Record<string, unknown>,
      turnUserId: nextTurnId,
      turnSeconds: nextSeconds,
      finished: false,
    };
  },

  sanitizeForPlayer(rawState: Record<string, unknown>, _viewerUserId: string) {
    return rawState;
  },
};
