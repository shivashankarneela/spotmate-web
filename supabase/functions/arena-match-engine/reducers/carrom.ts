import { ArenaGameReducer, ArenaPlayerMeta, ReducerResult } from "./types.ts";

/**
 * Deterministic Server-Authoritative Carrom Reducer (1v1 or 2v2)
 * - Normalized 1000x1000 playing surface with 4 corner pockets.
 * - Classic 19-coin setup: 1 Pink Queen at center + 9 White + 9 Black in 2 hexagonal rings.
 * - Fixed-timestep 2D elastic circle-circle collisions, wall bounce, and surface friction.
 * - Full rules: Queen + Cover (must pocket own coin on same or next shot), striker foul
 *   (returns 1 own coin to center), and extra turn on legal coin pocket.
 */

export type CoinColor = "white" | "black" | "queen";

export interface CarromCoin {
  id: string;
  color: CoinColor;
  x: number; // 0..1000
  y: number; // 0..1000
  pocketed: boolean;
}

export interface CarromShotLog {
  user_id: string;
  display_name: string;
  striker_x: number;
  angle_rad: number;
  power: number;
  pocketed_colors: CoinColor[];
  foul: boolean;
  queen_covered: boolean;
  extra_turn: boolean;
}

export interface CarromState {
  /** Team color assigned per user_id: 'white' (even seats) or 'black' (odd seats) */
  team_color: Record<string, "white" | "black">;
  coins: CarromCoin[];
  turn_index: number;
  queen_holder: "white" | "black" | null;
  queen_pending_cover_by: "white" | "black" | null;
  pocketed_counts: { white: number; black: number };
  last_shot: CarromShotLog | null;
}

const BOARD_SIZE = 1000;
const WALL_MARGIN = 46;
const POCKET_RADIUS = 44;
const COIN_RADIUS = 24;
const STRIKER_RADIUS = 30;
const SUBSTEPS = 4;
const FRICTION = Math.pow(0.985, 1 / SUBSTEPS);
const RESTITUTION = 0.88;
const MAX_SIM_STEPS = 420;
const TURN_SECONDS = 20;

const POCKETS = [
  { x: WALL_MARGIN + 8, y: WALL_MARGIN + 8 },
  { x: BOARD_SIZE - WALL_MARGIN - 8, y: WALL_MARGIN + 8 },
  { x: WALL_MARGIN + 8, y: BOARD_SIZE - WALL_MARGIN - 8 },
  { x: BOARD_SIZE - WALL_MARGIN - 8, y: BOARD_SIZE - WALL_MARGIN - 8 },
];

function buildInitialCoins(): CarromCoin[] {
  const coins: CarromCoin[] = [];
  const cx = 500;
  const cy = 500;
  const r = COIN_RADIUS * 2.04;

  // Center Queen
  coins.push({ id: "queen", color: "queen", x: cx, y: cy, pocketed: false });

  let wIdx = 1;
  let bIdx = 1;

  // Inner ring of 6 alternating coins
  for (let i = 0; i < 6; i++) {
    const ang = (i * Math.PI) / 3;
    const isWhite = i % 2 === 0;
    coins.push({
      id: isWhite ? `w${wIdx++}` : `b${bIdx++}`,
      color: isWhite ? "white" : "black",
      x: cx + Math.cos(ang) * r,
      y: cy + Math.sin(ang) * r,
      pocketed: false,
    });
  }

  // Outer ring of 12 coins (6 white, 6 black)
  for (let i = 0; i < 12; i++) {
    const ang = (i * Math.PI) / 6;
    const dist = i % 2 === 0 ? r * 2 : r * Math.sqrt(3);
    const isWhite = i % 2 === 0;
    coins.push({
      id: isWhite ? `w${wIdx++}` : `b${bIdx++}`,
      color: isWhite ? "white" : "black",
      x: cx + Math.cos(ang) * dist,
      y: cy + Math.sin(ang) * dist,
      pocketed: false,
    });
  }

  return coins; // 1 queen + 9 white + 9 black = 19 coins
}

interface SimBody {
  id: string;
  isStriker: boolean;
  color?: CoinColor;
  x: number;
  y: number;
  vx: number;
  vy: number;
  r: number;
  mass: number;
  pocketed: boolean;
}

function simulateShot(
  coins: CarromCoin[],
  strikerX: number,
  strikerY: number,
  angleRad: number,
  power: number,
) {
  const speed = 10 + power * 26;
  const bodies: SimBody[] = [
    {
      id: "striker",
      isStriker: true,
      x: strikerX,
      y: strikerY,
      vx: Math.cos(angleRad) * speed,
      vy: Math.sin(angleRad) * speed,
      r: STRIKER_RADIUS,
      mass: 2.2,
      pocketed: false,
    },
    ...coins
      .filter((c) => !c.pocketed)
      .map((c) => ({
        id: c.id,
        isStriker: false,
        color: c.color,
        x: c.x,
        y: c.y,
        vx: 0,
        vy: 0,
        r: COIN_RADIUS,
        mass: 1.0,
        pocketed: false,
      })),
  ];

  const newlyPocketed: CoinColor[] = [];
  let strikerPocketed = false;

  for (let step = 0; step < MAX_SIM_STEPS * SUBSTEPS; step++) {
    let anyMoving = false;

    for (const b of bodies) {
      if (b.pocketed) continue;
      b.x += b.vx / SUBSTEPS;
      b.y += b.vy / SUBSTEPS;
      b.vx *= FRICTION;
      b.vy *= FRICTION;
      if (Math.hypot(b.vx, b.vy) < 0.08) {
        b.vx = 0;
        b.vy = 0;
      } else {
        anyMoving = true;
      }

      // Check pockets
      for (const p of POCKETS) {
        if (Math.hypot(b.x - p.x, b.y - p.y) < POCKET_RADIUS) {
          b.pocketed = true;
          b.vx = 0;
          b.vy = 0;
          if (b.isStriker) {
            strikerPocketed = true;
          } else if (b.color) {
            newlyPocketed.push(b.color);
          }
          break;
        }
      }
      if (b.pocketed) continue;

      // Wall bounce
      const minB = WALL_MARGIN + b.r;
      const maxB = BOARD_SIZE - WALL_MARGIN - b.r;
      if (b.x < minB) {
        b.x = minB;
        b.vx = Math.abs(b.vx) * RESTITUTION;
      } else if (b.x > maxB) {
        b.x = maxB;
        b.vx = -Math.abs(b.vx) * RESTITUTION;
      }
      if (b.y < minB) {
        b.y = minB;
        b.vy = Math.abs(b.vy) * RESTITUTION;
      } else if (b.y > maxB) {
        b.y = maxB;
        b.vy = -Math.abs(b.vy) * RESTITUTION;
      }
    }

    // Pairwise elastic collisions
    for (let i = 0; i < bodies.length; i++) {
      const a = bodies[i];
      if (a.pocketed) continue;
      for (let j = i + 1; j < bodies.length; j++) {
        const b = bodies[j];
        if (b.pocketed) continue;
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const dist = Math.hypot(dx, dy);
        const minDist = a.r + b.r;
        if (dist > 0 && dist < minDist) {
          const nx = dx / dist;
          const ny = dy / dist;
          const overlap = (minDist - dist) * 0.5;
          a.x -= nx * overlap;
          a.y -= ny * overlap;
          b.x += nx * overlap;
          b.y += ny * overlap;

          const rvx = b.vx - a.vx;
          const rvy = b.vy - a.vy;
          const velAlongNormal = rvx * nx + rvy * ny;
          if (velAlongNormal < 0) {
            const invMassA = 1 / a.mass;
            const invMassB = 1 / b.mass;
            const imp = (-(1 + RESTITUTION) * velAlongNormal) / (invMassA + invMassB);
            a.vx -= imp * invMassA * nx;
            a.vy -= imp * invMassA * ny;
            b.vx += imp * invMassB * nx;
            b.vy += imp * invMassB * ny;
          }
        }
      }
    }

    if (!anyMoving) break;
  }

  // Write final coin positions back
  const byId = new Map(bodies.map((b) => [b.id, b]));
  const updatedCoins = coins.map((c) => {
    const sim = byId.get(c.id);
    if (!sim) return c;
    return {
      ...c,
      x: Math.round(sim.x * 10) / 10,
      y: Math.round(sim.y * 10) / 10,
      pocketed: sim.pocketed,
    };
  });

  return { updatedCoins, newlyPocketed, strikerPocketed };
}

export const carromReducer: ArenaGameReducer = {
  gameType: "carrom",

  initState(players: ArenaPlayerMeta[]) {
    if (players.length !== 2 && players.length !== 4) {
      throw new Error("Carrom supports 1v1 (2 players) or 2v2 (4 players).");
    }
    const teamColor: Record<string, "white" | "black"> = {};
    players.forEach((p, idx) => {
      teamColor[p.user_id] = idx % 2 === 0 ? "white" : "black";
    });

    const state: CarromState = {
      team_color: teamColor,
      coins: buildInitialCoins(),
      turn_index: 0,
      queen_holder: null,
      queen_pending_cover_by: null,
      pocketed_counts: { white: 0, black: 0 },
      last_shot: null,
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
    const state: CarromState = structuredClone(rawState as unknown as CarromState);
    const currentPlayer = players[state.turn_index];
    if (!currentPlayer || currentPlayer.user_id !== actorUserId) {
      throw new Error("It is not your turn to strike.");
    }

    const myColor = state.team_color[actorUserId] ?? "white";
    const strikerNormX = payload.striker_x;
    const angleRad = payload.angle_rad;
    const power = payload.power;
    if (payload.type !== "shoot" ||
        typeof strikerNormX !== "number" || !Number.isFinite(strikerNormX) ||
        typeof angleRad !== "number" || !Number.isFinite(angleRad) ||
        typeof power !== "number" || !Number.isFinite(power) ||
        strikerNormX < 0.18 || strikerNormX > 0.82 || power < 0.15 || power > 1) {
      throw new Error("Choose a legal striker position and shot power.");
    }
    if (Math.sin(angleRad) * (myColor === "white" ? -1 : 1) <= 0.05) {
      throw new Error("Aim the striker into the board.");
    }

    // White shoots from bottom baseline (y = 835), Black shoots from top baseline (y = 165)
    const strikerX = strikerNormX * BOARD_SIZE;
    const strikerY = myColor === "white" ? 835 : 165;
    if (state.coins.some((coin) => !coin.pocketed &&
        Math.hypot(coin.x - strikerX, coin.y - strikerY) < STRIKER_RADIUS + COIN_RADIUS)) {
      throw new Error("Slide the striker clear of the coins before shooting.");
    }

    const { updatedCoins, newlyPocketed, strikerPocketed } = simulateShot(
      state.coins,
      strikerX,
      strikerY,
      angleRad,
      power,
    );
    state.coins = updatedCoins;

    const pocketedOwn = newlyPocketed.filter((c) => c === myColor).length;
    const pocketedQueen = newlyPocketed.includes("queen");
    let queenCovered = false;

    // Handle Striker Foul: return 1 pocketed own coin to center
    if (strikerPocketed) {
      const ownPocketed = state.coins.find((c) => c.color === myColor && c.pocketed);
      if (ownPocketed) {
        ownPocketed.pocketed = false;
        ownPocketed.x = 500;
        ownPocketed.y = 500;
      }
      // If Queen was pending cover, return Queen to center
      if (state.queen_pending_cover_by === myColor || pocketedQueen) {
        const q = state.coins.find((c) => c.color === "queen");
        if (q) {
          q.pocketed = false;
          q.x = 500;
          q.y = 500;
        }
        state.queen_pending_cover_by = null;
      }
    } else {
      // Handle Queen & Cover rules
      if (pocketedQueen && pocketedOwn > 0) {
        state.queen_holder = myColor;
        state.queen_pending_cover_by = null;
        queenCovered = true;
      } else if (pocketedQueen) {
        state.queen_pending_cover_by = myColor;
      } else if (state.queen_pending_cover_by === myColor) {
        if (pocketedOwn > 0) {
          state.queen_holder = myColor;
          state.queen_pending_cover_by = null;
          queenCovered = true;
        } else {
          // Failed to cover Queen -> return Queen to center
          const q = state.coins.find((c) => c.color === "queen");
          if (q) {
            q.pocketed = false;
            q.x = 500;
            q.y = 500;
          }
          state.queen_pending_cover_by = null;
        }
      }
    }

    // Recompute pocketed counts
    state.pocketed_counts = {
      white: state.coins.filter((c) => c.color === "white" && c.pocketed).length,
      black: state.coins.filter((c) => c.color === "black" && c.pocketed).length,
    };

    const queenResolved = state.queen_pending_cover_by === null;
    const whiteCleared = state.pocketed_counts.white === 9 && queenResolved;
    const blackCleared = state.pocketed_counts.black === 9 && queenResolved;

    if (whiteCleared || blackCleared) {
      const winningColor = whiteCleared ? "white" : "black";
      const winner =
        players.find((p) => state.team_color[p.user_id] === winningColor) ?? currentPlayer;

      state.last_shot = {
        user_id: actorUserId,
        display_name: currentPlayer.display_name,
        striker_x: strikerNormX,
        angle_rad: angleRad,
        power,
        pocketed_colors: newlyPocketed,
        foul: strikerPocketed,
        queen_covered: queenCovered,
        extra_turn: false,
      };

      return {
        nextState: state as unknown as Record<string, unknown>,
        turnUserId: null,
        turnSeconds: 0,
        finished: true,
        finalStatus: "completed",
        winnerUserId: winner.user_id,
        winReason: `${winner.display_name} cleared all 9 ${winningColor} coins${
          state.queen_holder === winningColor ? " + Queen!" : "!"
        }`,
      };
    }

    const extraTurn = !strikerPocketed && (pocketedOwn > 0 || pocketedQueen);
    if (!extraTurn) {
      state.turn_index = (state.turn_index + 1) % players.length;
    }

    state.last_shot = {
      user_id: actorUserId,
      display_name: currentPlayer.display_name,
      striker_x: strikerNormX,
      angle_rad: angleRad,
      power,
      pocketed_colors: newlyPocketed,
      foul: strikerPocketed,
      queen_covered: queenCovered,
      extra_turn: extraTurn,
    };

    return {
      nextState: state as unknown as Record<string, unknown>,
      turnUserId: players[state.turn_index].user_id,
      turnSeconds: TURN_SECONDS,
      finished: false,
    };
  },

  sanitizeForPlayer(rawState: Record<string, unknown>, _viewerUserId: string) {
    return rawState;
  },
};
