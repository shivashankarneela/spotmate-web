import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { carromReducer } from "./reducers/carrom.ts";
import { chessReducer } from "./reducers/chess.ts";
import { handCricketReducer } from "./reducers/hand_cricket.ts";
import { ludoReducer } from "./reducers/ludo.ts";
import { snakesLaddersReducer } from "./reducers/snakes_ladders.ts";
import { ArenaGameReducer, ArenaGameType, ArenaPlayerMeta } from "./reducers/types.ts";

/**
 * Complete 5-Game arena-match-engine (Phase 5)
 * Registers: hand_cricket, snakes_ladders, ludo, chess (+ ELO), and carrom (1v1 / 2v2).
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ExtendedGameType = ArenaGameType | "carrom";

const REDUCERS: Partial<Record<ExtendedGameType, ArenaGameReducer>> = {
  hand_cricket: handCricketReducer,
  snakes_ladders: snakesLaddersReducer,
  ludo: ludoReducer,
  chess: chessReducer,
  carrom: carromReducer,
};

interface ArenaRequest {
  action:
    | "queue.join"
    | "queue.leave"
    | "challenge.create"
    | "challenge.respond"
    | "match.state"
    | "match.move"
    | "match.claim_timeout"
    | "match.resign";
  game_type?: ExtendedGameType;
  player_count?: number;
  stake_sc?: number;
  display_name?: string;
  avatar_url?: string;
  to_spotmate_id?: string;
  challenge_id?: string;
  accept?: boolean;
  match_id?: string;
  move_payload?: Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: authData, error: authErr } = await userClient.auth.getUser();
    if (authErr || !authData?.user) return json({ error: "Unauthorized" }, 401);

    const userId = authData.user.id;
    const admin = createClient(supabaseUrl, serviceKey);
    const body: ArenaRequest = await req.json();

    if (body.action === "queue.join") {
      const gameType: ExtendedGameType = body.game_type ?? "carrom";
      const stakeSc = Math.max(0, Math.floor(body.stake_sc ?? 0));
      const playerCount = gameType === "chess" || gameType === "hand_cricket"
        ? 2
        : gameType === "carrom"
        ? (body.player_count === 4 ? 4 : 2)
        : Math.min(4, Math.max(2, Math.floor(body.player_count ?? 2)));
      const displayName = (body.display_name ?? "Player").trim();

      const reducer = REDUCERS[gameType];
      if (!reducer) return json({ error: `${gameType} is not enabled.` }, 501);

      await admin
        .from("arena_matchmaking_queue")
        .update({ status: "expired" })
        .eq("status", "waiting")
        .lt("expires_at", new Date().toISOString());

      await admin
        .from("arena_matchmaking_queue")
        .update({ status: "cancelled" })
        .eq("user_id", userId)
        .eq("status", "waiting");

      const { data: myEntry, error: qErr } = await admin
        .from("arena_matchmaking_queue")
        .insert({
          user_id: userId,
          display_name: displayName,
          avatar_url: body.avatar_url ?? null,
          game_type: gameType,
          player_count: playerCount,
          stake_sc: stakeSc,
        })
        .select("*")
        .single();
      if (qErr) return json({ error: qErr.message }, 500);

      const { data: pool } = await admin
        .from("arena_matchmaking_queue")
        .select("*")
        .eq("game_type", gameType)
        .eq("player_count", playerCount)
        .eq("stake_sc", stakeSc)
        .eq("status", "waiting")
        .order("created_at", { ascending: true })
        .limit(playerCount);

      if (pool && pool.length === playerCount) {
        const ids = pool.map((r) => r.id);
        const { data: claimed } = await admin
          .from("arena_matchmaking_queue")
          .update({ status: "matched" })
          .in("id", ids)
          .eq("status", "waiting")
          .select("*");

        if (claimed && claimed.length === playerCount) {
          const players: ArenaPlayerMeta[] = claimed.map((c) => ({
            user_id: c.user_id,
            display_name: c.display_name,
            avatar_url: c.avatar_url,
          }));
          const match = await createMatchWithEscrow(admin, reducer, "random_queue", stakeSc, players);
          await admin.from("arena_matchmaking_queue").update({ matched_id: match.id }).in("id", ids);
          await broadcastMatchEvent(admin, match.id, "match_started", { match_id: match.id });

          return json({
            matched: true,
            joined_count: playerCount,
            required_count: playerCount,
            match_id: match.id,
            match: sanitizeMatchForViewer(match, reducer, userId),
          });
        }
      }

      return json({
        matched: false,
        joined_count: pool?.length ?? 1,
        required_count: playerCount,
        queue_entry: myEntry,
      });
    }

    if (body.action === "queue.leave") {
      await admin
        .from("arena_matchmaking_queue")
        .update({ status: "cancelled" })
        .eq("user_id", userId)
        .eq("status", "waiting");
      return json({ ok: true });
    }

    if (body.action === "challenge.create") {
      const targetSpotmateId = (body.to_spotmate_id ?? "").trim();
      if (!targetSpotmateId) return json({ error: "to_spotmate_id is required" }, 400);
      const gameType: ExtendedGameType = body.game_type ?? "carrom";
      const stakeSc = Math.max(0, Math.floor(body.stake_sc ?? 0));

      const { data: targetProfile } = await admin
        .from("user_profiles")
        .select("id")
        .eq("spotmate_id",targetSpotmateId.toUpperCase())
        .limit(1)
        .maybeSingle();

      if (!targetProfile) return json({ error: `No Spotmate player found for "${targetSpotmateId}".` }, 404);
      if (targetProfile.id === userId) return json({ error: "You cannot challenge yourself." }, 400);

      const { data: challenge, error: cErr } = await admin
        .from("arena_game_challenges")
        .insert({
          from_user_id: userId,
          from_name: (body.display_name ?? "Player").trim(),
          from_avatar_url: body.avatar_url ?? null,
          to_user_id: targetProfile.id,
          to_spotmate_id: targetSpotmateId,
          game_type: gameType,
          stake_sc: stakeSc,
        })
        .select("*")
        .single();
      if (cErr) return json({ error: cErr.message }, 500);
      return json({ challenge }, 201);
    }

    if (body.action === "challenge.respond") {
      if (!body.challenge_id) return json({ error: "challenge_id is required" }, 400);
      const { data: ch } = await admin
        .from("arena_game_challenges")
        .select("*")
        .eq("id", body.challenge_id)
        .eq("to_user_id", userId)
        .eq("status", "pending")
        .maybeSingle();

      if (!ch) return json({ error: "Challenge not found or already answered." }, 404);
      if (new Date(ch.expires_at).getTime() <= Date.now()) return json({ error: "Challenge expired." }, 410);
      if (!body.accept) {
        const {data: declined, error} = await admin.from("arena_game_challenges")
          .update({ status: "declined" }).eq("id", ch.id).eq("status", "pending")
          .gt("expires_at", new Date().toISOString()).select("id").maybeSingle();
        if (error) throw error;
        if (!declined) return json({error:"Challenge expired or already answered."},409);
        return json({ declined: true });
      }

      const reducer = REDUCERS[ch.game_type as ExtendedGameType];
      if (!reducer) return json({ error: `${ch.game_type} is not enabled yet.` }, 501);

      const players: ArenaPlayerMeta[] = [
        { user_id: ch.from_user_id, display_name: ch.from_name, avatar_url: ch.from_avatar_url },
        { user_id: userId, display_name: (body.display_name ?? "Player").trim(), avatar_url: body.avatar_url ?? null },
      ];
      const initial = reducer.initState(players);
      const {data: match, error: acceptError} = await admin.rpc("arena_accept_challenge_atomic", {
        p_challenge: ch.id, p_user: userId, p_players: players, p_state: initial.state,
        p_turn: initial.turnUserId, p_turn_seconds: initial.turnSeconds,
      });
      if (acceptError) throw acceptError;
      return json({ accepted: true, match_id: match.id, match: sanitizeMatchForViewer(match, reducer, userId) });
    }

    if (!body.match_id) return json({ error: "match_id is required" }, 400);
    const { data: match } = await admin.from("arena_game_matches").select("*").eq("id", body.match_id).maybeSingle();
    if (!match) return json({ error: "Match not found." }, 404);
    if (!(match.player_ids as string[]).includes(userId)) return json({ error: "Forbidden" }, 403);

    const reducer = REDUCERS[match.game_type as ExtendedGameType];
    if (!reducer) return json({ error: `Unsupported game_type: ${match.game_type}` }, 500);

    if (body.action === "match.state") return json({ match: sanitizeMatchForViewer(match, reducer, userId) });
    if (match.status !== "active") return json({ match: sanitizeMatchForViewer(match, reducer, userId), already_finished: true });

    if (body.action === "match.resign") {
      const winnerId = (match.player_ids as string[]).find((id) => id !== userId) ?? null;
      const finalState = await maybeApplyChessElo(admin, match, match.state_json, winnerId, "forfeit");
      await admin.rpc("arena_settle_match", {
        p_match_id: match.id,
        p_final_status: "forfeit",
        p_winner_user_id: winnerId,
        p_win_reason: "Opponent resigned.",
        p_final_state: finalState,
      });
      await broadcastMatchEvent(admin, match.id, "match_updated", { match_id: match.id });
      const { data: updated } = await admin.from("arena_game_matches").select("*").eq("id", match.id).single();
      return json({ match: sanitizeMatchForViewer(updated, reducer, userId) });
    }

    if (body.action === "match.claim_timeout") {
      if (new Date(match.turn_expires_at).getTime() > Date.now()) {
        return json({ error: "Turn timer has not expired yet." }, 400);
      }
      const timedOutId = match.turn_user_id;
      const winnerId = (match.player_ids as string[]).find((id) => id !== timedOutId) ?? userId;
      const finalState = await maybeApplyChessElo(admin, match, match.state_json, winnerId, "forfeit");
      await admin.rpc("arena_settle_match", {
        p_match_id: match.id,
        p_final_status: "forfeit",
        p_winner_user_id: winnerId,
        p_win_reason: "Player timed out.",
        p_final_state: finalState,
      });
      await broadcastMatchEvent(admin, match.id, "match_updated", { match_id: match.id });
      const { data: updated } = await admin.from("arena_game_matches").select("*").eq("id", match.id).single();
      return json({ match: sanitizeMatchForViewer(updated, reducer, userId) });
    }

    if (body.action === "match.move") {
      const result = reducer.applyAction(
        match.state_json,
        match.players_meta as ArenaPlayerMeta[],
        userId,
        body.move_payload ?? {},
      );

      if (result.finished) {
        const finalState = await maybeApplyChessElo(
          admin,
          match,
          result.nextState,
          result.winnerUserId ?? null,
          result.finalStatus ?? "completed",
        );
        await admin.rpc("arena_settle_match", {
          p_match_id: match.id,
          p_final_status: result.finalStatus ?? "completed",
          p_winner_user_id: result.winnerUserId ?? null,
          p_win_reason: result.winReason ?? "Match completed.",
          p_final_state: finalState,
        });
      } else {
        const nextExpires = new Date(Date.now() + result.turnSeconds * 1000).toISOString();
        await admin
          .from("arena_game_matches")
          .update({
            state_json: result.nextState,
            turn_user_id: result.turnUserId,
            turn_expires_at: nextExpires,
            updated_at: new Date().toISOString(),
          })
          .eq("id", match.id);
      }

      await broadcastMatchEvent(admin, match.id, "match_updated", { match_id: match.id });
      const { data: updated } = await admin.from("arena_game_matches").select("*").eq("id", match.id).single();
      return json({ match: sanitizeMatchForViewer(updated, reducer, userId) });
    }

    return json({ error: `Unknown action: ${body.action}` }, 400);
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 400);
  }
});

async function maybeApplyChessElo(
  admin: ReturnType<typeof createClient>,
  match: Record<string, unknown>,
  state: Record<string, unknown>,
  winnerId: string | null,
  status: string,
): Promise<Record<string, unknown>> {
  if (match.game_type !== "chess") return state;
  const whiteId = String(state.white_id ?? "");
  const blackId = String(state.black_id ?? "");
  if (!whiteId || !blackId) return state;

  const outcome =
    status === "draw" || !winnerId ? "draw" : winnerId === whiteId ? "white" : "black";

  const { data: elo } = await admin.rpc("arena_update_chess_elo", {
    p_white_id: whiteId,
    p_black_id: blackId,
    p_outcome: outcome,
  });
  return { ...state, elo_summary: elo ?? null };
}

async function createMatchWithEscrow(
  admin: ReturnType<typeof createClient>,
  reducer: ArenaGameReducer,
  sourceMode: "random_queue" | "spotmate_id",
  stakeSc: number,
  players: ArenaPlayerMeta[],
) {
  const init = reducer.initState(players);
  const playerIds = players.map((p) => p.user_id);
  const potSc = stakeSc * players.length;
  const turnExpiresAt = new Date(Date.now() + init.turnSeconds * 1000).toISOString();

  const { data: match, error: mErr } = await admin
    .from("arena_game_matches")
    .insert({
      game_type: reducer.gameType,
      source_mode: sourceMode,
      stake_sc: stakeSc,
      pot_sc: potSc,
      player_ids: playerIds,
      players_meta: players,
      state_json: init.state,
      turn_user_id: init.turnUserId,
      turn_expires_at: turnExpiresAt,
    })
    .select("*")
    .single();
  if (mErr || !match) throw new Error(mErr?.message ?? "Failed to create match");

  if (stakeSc > 0) {
    const { error: lockErr } = await admin.rpc("arena_lock_match_escrow", {
      p_match_id: match.id,
      p_player_ids: playerIds,
      p_stake_sc: stakeSc,
    });
    if (lockErr) {
      await admin.from("arena_game_matches").update({ status: "cancelled" }).eq("id", match.id);
      throw new Error(lockErr.message);
    }
  }
  return match;
}

function sanitizeMatchForViewer(
  match: Record<string, unknown>,
  reducer: ArenaGameReducer,
  viewerUserId: string,
) {
  return {
    id: match.id,
    game_type: match.game_type,
    source_mode: match.source_mode,
    stake_sc: match.stake_sc,
    pot_sc: match.pot_sc,
    players_meta: match.players_meta,
    state: reducer.sanitizeForPlayer(match.state_json as Record<string, unknown>, viewerUserId),
    turn_user_id: match.turn_user_id,
    turn_expires_at: match.turn_expires_at,
    status: match.status,
    winner_user_id: match.winner_user_id,
    win_reason: match.win_reason,
    created_at: match.created_at,
    finished_at: match.finished_at,
  };
}

async function broadcastMatchEvent(
  admin: ReturnType<typeof createClient>,
  matchId: string,
  event: string,
  payload: Record<string, unknown>,
) {
  const channel = admin.channel(`arena_match_${matchId}`);
  await channel.send({ type: "broadcast", event, payload });
  await admin.removeChannel(channel);
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
