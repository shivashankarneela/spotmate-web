import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Spotmate Music Room Edge Function (`music-room-engine`)
 * - Free Rooms: 0 SC, 30 min cap, max 5 members, empty-room auto-close + next-batch allocation.
 * - Custom Rooms: 5 SC (30 min) or 10 SC (60 min), Room Code + Spotmate ID/User ID invites.
 * - Host-Only Groovy-Style Commands in Chat: !play, !pause, !resume, !skip, !queue, !np, !stop, !help.
 * - Supports YouTube Video + Audio sync (by URL, video ID, or YouTube Data API search) + HLS audio streams.
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface MusicRequest {
  action:
    | "rooms.list_free"
    | "room.create_free"
    | "room.create_custom"
    | "room.join"
    | "room.join_by_code"
    | "room.join_waitlist"
    | "room.leave"

    | "room.sync_state"
    | "chat.send";
  room_id?: string;
  room_code?: string;
  title?: string;
  duration_minutes?: number;
  display_name?: string;
  avatar_url?: string;
  to_identifier?: string; // Spotmate ID or User ID (UUID)
  message?: string;
}

function extractYoutubeVideoId(input: string): string | null {
  const trimmed = input.trim();
  if (/^[a-zA-Z0-9_-]{11}$/.test(trimmed)) return trimmed;
  const patterns = [
    /(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/|youtube\.com\/shorts\/)([a-zA-Z0-9_-]{11})/,
  ];
  for (const re of patterns) {
    const m = trimmed.match(re);
    if (m) return m[1];
  }
  return null;
}

function isAudioStreamUrl(input: string): boolean {
  return /^https?:\/\/.+\.(m3u8|mp3|aac|ogg)(\?.*)?$/i.test(input.trim());
}

async function resolvePlayableTrack(query: string): Promise<{
  source_type: "youtube" | "hls_audio";
  source_ref: string;
  title: string;
} | null> {
  const trimmed = query.trim();
  if (!trimmed) return null;

  if (isAudioStreamUrl(trimmed)) {
    return { source_type: "hls_audio", source_ref: trimmed, title: "Live Audio Stream" };
  }

  const directId = extractYoutubeVideoId(trimmed);
  if (directId) {
    return { source_type: "youtube", source_ref: directId, title: `YouTube Track (${directId})` };
  }

  // Optional YouTube Data API v3 search (set YOUTUBE_API_KEY in Supabase Edge Function secrets)
  const ytKey = Deno.env.get("YOUTUBE_API_KEY");
  if (!ytKey) return null;

  const url =
    `https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&videoEmbeddable=true&maxResults=1` +
    `&q=${encodeURIComponent(trimmed)}&key=${encodeURIComponent(ytKey)}`;
  const res = await fetch(url);
  if (!res.ok) return null;
  const data = await res.json();
  const first = data?.items?.[0];
  if (!first?.id?.videoId) return null;

  return {
    source_type: "youtube",
    source_ref: first.id.videoId,
    title: first.snippet?.title ?? trimmed,
  };
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
    const body: MusicRequest = await req.json();
    const displayName = (body.display_name ?? "Listener").trim();

    // Auto-close expired rooms before handling requests
    await admin
      .from("music_rooms")
      .update({ status: "closed", is_playing: false, closed_at: new Date().toISOString() })
      .eq("status", "active")
      .lt("expires_at", new Date().toISOString());

    // -------------------------------------------------------------------------
    // 1. LIST AVAILABLE FREE ROOMS (with live member counts)
    // -------------------------------------------------------------------------
    if (body.action === "rooms.list_free") {
      const { data: rooms } = await admin
        .from("music_rooms")
        .select("*, music_room_members(user_id, display_name, avatar_url)")
        .eq("mode", "free")
        .eq("status", "active")
        .order("created_at", { ascending: false });

      const formatted = (rooms ?? []).map((r) => ({
        ...r,
        member_count: Array.isArray(r.music_room_members) ? r.music_room_members.length : 0,
      }));
      return json({ rooms: formatted, server_now_ms: Date.now() });
    }

    // -------------------------------------------------------------------------
    // 2. CREATE FREE ROOM (0 SC, 30 min, max 5 members)
    // -------------------------------------------------------------------------
    if (body.action === "room.create_free") {
      const { data: codeData } = await admin.rpc("generate_music_room_code");
      const roomCode = String(codeData ?? `SPOT-${Math.floor(1000 + Math.random() * 9000)}`);
      const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString();

      const { data: room, error: rErr } = await admin
        .from("music_rooms")
        .insert({
          room_code: roomCode,
          title: (body.title ?? `${displayName}'s Free Lounge`).trim(),
          mode: "free",
          duration_minutes: 30,
          cost_sc: 0,
          max_members: 5,
          host_user_id: userId,
          expires_at: expiresAt,
        })
        .select("*")
        .single();
      if (rErr) return json({ error: rErr.message }, 500);

      await admin.from("music_room_members").insert({
        room_id: room.id,
        user_id: userId,
        display_name: displayName,
        avatar_url: body.avatar_url ?? null,
      });

      await postBotMessage(
        admin,
        room.id,
        `Free 30-min Music Room started (max 5 seats). Host can type !play <song or YouTube link> to start!`,
      );
      return json({ room, server_now_ms: Date.now() }, 201);
    }

    // -------------------------------------------------------------------------
    // 3. CREATE CUSTOM ROOM (30 min = 5 SC, 60 min = 10 SC)
    // -------------------------------------------------------------------------
    if (body.action === "room.create_custom") {
      const duration = body.duration_minutes === 60 ? 60 : 30;
      const { data: room, error: cErr } = await admin.rpc("music_create_custom_room", {
        p_host_id: userId,
        p_host_name: displayName,
        p_host_avatar_url: body.avatar_url ?? null,
        p_title: body.title ?? `${displayName}'s Music Room`,
        p_duration_minutes: duration,
      });
      if (cErr) return json({ error: cErr.message }, 400);
      return json({ room, server_now_ms: Date.now() }, 201);
    }

    // -------------------------------------------------------------------------
    // 4. JOIN ROOM (by room_id OR room_code)
    // -------------------------------------------------------------------------
    if (body.action === "room.join" || body.action === "room.join_by_code") {
      let targetRoomId = body.room_id;
      if (body.action === "room.join_by_code") {
        const code = (body.room_code ?? "").trim().toUpperCase();
        const { data: found } = await admin
          .from("music_rooms")
          .select("id")
          .eq("room_code", code)
          .eq("status", "active")
          .maybeSingle();
        if (!found) return json({ error: `No active room found for code "${code}".` }, 404);
        targetRoomId = found.id;
      }

      if (!targetRoomId) return json({ error: "room_id is required" }, 400);

      const { data: room, error: jErr } = await admin.rpc("music_join_room_atomic", {
        p_room_id: targetRoomId,
        p_user_id: userId,
        p_display_name: displayName,
        p_avatar_url: body.avatar_url ?? null,
      });
      if (jErr) return json({ error: jErr.message }, 400);
      return json({ room, server_now_ms: Date.now() });
    }

    // -------------------------------------------------------------------------
    // 5. JOIN NEXT-BATCH WAITLIST (when all Free rooms are full)
    // -------------------------------------------------------------------------
    if (body.action === "room.join_waitlist") {
      await admin
        .from("music_room_waitlist")
        .update({ status: "cancelled" })
        .eq("user_id", userId)
        .eq("status", "waiting");

      const { data: entry, error: wErr } = await admin
        .from("music_room_waitlist")
        .insert({
          user_id: userId,
          display_name: displayName,
          avatar_url: body.avatar_url ?? null,
        })
        .select("*")
        .single();
      if (wErr) return json({ error: wErr.message }, 500);
      return json({ waitlist_entry: entry }, 201);
    }

    // -------------------------------------------------------------------------
    // 6. LEAVE ROOM (Auto-transfer Host or Close Empty & Allocate Next Batch)
    // -------------------------------------------------------------------------
    if (body.action === "room.leave") {
      if (!body.room_id) return json({ error: "room_id is required" }, 400);
      const { data: res } = await admin.rpc("music_leave_and_reallocate", {
        p_room_id: body.room_id,
        p_user_id: userId,
      });
      return json({ result: res });
    }

    // -------------------------------------------------------------------------
    // 7. INVITE FRIEND TO CUSTOM ROOM BY SPOTMATE ID OR USER ID
    // -------------------------------------------------------------------------


    // -------------------------------------------------------------------------
    // 8. SYNC STATE (Returns room, members, queue, and exact server_now_ms)
    // -------------------------------------------------------------------------
    if (body.action === "room.sync_state") {
      if (!body.room_id) return json({ error: "room_id is required" }, 400);
      const [{ data: room }, { data: members }, { data: queue }] = await Promise.all([
        admin.from("music_rooms").select("*").eq("id", body.room_id).maybeSingle(),
        admin
          .from("music_room_members")
          .select("*")
          .eq("room_id", body.room_id)
          .order("joined_at", { ascending: true }),
        admin
          .from("music_room_queue")
          .select("*")
          .eq("room_id", body.room_id)
          .eq("status", "queued")
          .order("created_at", { ascending: true }),
      ]);
      return json({
        room,
        members: members ?? [],
        queue: queue ?? [],
        server_now_ms: Date.now(),
      });
    }

    // -------------------------------------------------------------------------
    // 9. IN-ROOM CHAT + HOST-ONLY GROOVY COMMANDS (!play, !pause, !skip, ...)
    // -------------------------------------------------------------------------
    if (body.action === "chat.send") {
      if (!body.room_id || !body.message?.trim()) {
        return json({ error: "room_id and message are required" }, 400);
      }
      const msg = body.message.trim().slice(0, 300);

      const { data: room } = await admin
        .from("music_rooms")
        .select("*")
        .eq("id", body.room_id)
        .eq("status", "active")
        .maybeSingle();
      if (!room) return json({ error: "Room is closed or expired." }, 410);

      const isCommand = msg.startsWith("!");
      await admin.from("music_room_messages").insert({
        room_id: room.id,
        user_id: userId,
        display_name: displayName,
        kind: isCommand ? "command" : "chat",
        content: msg,
      });

      if (!isCommand) return json({ ok: true });

      // Parse command & enforce Host-Only playback control
      const [rawCmd, ...argParts] = msg.split(/\s+/);
      const cmd = rawCmd.toLowerCase();
      const arg = argParts.join(" ").trim();

      if (cmd === "!help") {
        await postBotMessage(
          admin,
          room.id,
          "Host Commands: !play <song or YouTube link>, !pause, !resume, !skip, !queue, !np, !stop",
        );
        return json({ ok: true });
      }

      if (cmd === "!np") {
        const text = room.current_title
          ? `🎵 Now Playing: ${room.current_title} (${room.is_playing ? "Playing" : "Paused"})`
          : "Nothing is playing right now. Host can type !play <song>.";
        await postBotMessage(admin, room.id, text);
        return json({ ok: true });
      }

      if (cmd === "!queue") {
        const { data: q } = await admin
          .from("music_room_queue")
          .select("title")
          .eq("room_id", room.id)
          .eq("status", "queued")
          .order("created_at", { ascending: true })
          .limit(5);
        const listText =
          q && q.length > 0
            ? `Up next: ${q.map((t, i) => `${i + 1}. ${t.title}`).join(" | ")}`
            : "Queue is empty.";
        await postBotMessage(admin, room.id, listText);
        return json({ ok: true });
      }

      // All playback-mutating commands require Host role
      if (room.host_user_id !== userId) {
        await postBotMessage(
          admin,
          room.id,
          `Only the Room Host can run ${cmd}.`,
        );
        return json({ ok: true, host_only: true });
      }

      if (cmd === "!play") {
        if (!arg) {
          await postBotMessage(admin, room.id, "Usage: !play <YouTube URL or song name>");
          return json({ ok: true });
        }
        const track = await resolvePlayableTrack(arg);
        if (!track) {
          await postBotMessage(
            admin,
            room.id,
            "Paste a YouTube video link (or configure YOUTUBE_API_KEY for song-name search).",
          );
          return json({ ok: true });
        }

        // If nothing is currently playing -> start immediately; else add to queue
        if (!room.current_source_ref) {
          await admin
            .from("music_rooms")
            .update({
              current_source_type: track.source_type,
              current_source_ref: track.source_ref,
              current_title: track.title,
              started_at: new Date().toISOString(),
              seek_offset_ms: 0,
              is_playing: true,
            })
            .eq("id", room.id);

          await postBotMessage(admin, room.id, `🎵 Now Playing — ${track.title} (Synced)`);
        } else {
          await admin.from("music_room_queue").insert({
            room_id: room.id,
            added_by: userId,
            source_type: track.source_type,
            source_ref: track.source_ref,
            title: track.title,
            status: "queued",
          });
          await postBotMessage(admin, room.id, `➕ Queued: ${track.title}`);
        }
        return json({ ok: true });
      }

      if (cmd === "!pause") {
        const elapsed = room.started_at
          ? Date.now() - new Date(room.started_at).getTime()
          : 0;
        const newOffset = room.is_playing ? (room.seek_offset_ms ?? 0) + elapsed : room.seek_offset_ms;
        await admin
          .from("music_rooms")
          .update({ is_playing: false, seek_offset_ms: Math.max(0, newOffset) })
          .eq("id", room.id);
        await postBotMessage(admin, room.id, "⏸ Playback paused by Host.");
        return json({ ok: true });
      }

      if (cmd === "!resume") {
        await admin
          .from("music_rooms")
          .update({ is_playing: true, started_at: new Date().toISOString() })
          .eq("id", room.id);
        await postBotMessage(admin, room.id, "▶️ Playback resumed by Host.");
        return json({ ok: true });
      }

      if (cmd === "!skip") {
        const { data: next } = await admin
          .from("music_room_queue")
          .select("*")
          .eq("room_id", room.id)
          .eq("status", "queued")
          .order("created_at", { ascending: true })
          .limit(1)
          .maybeSingle();

        if (next) {
          await admin.from("music_room_queue").update({ status: "playing" }).eq("id", next.id);
          await admin
            .from("music_rooms")
            .update({
              current_source_type: next.source_type,
              current_source_ref: next.source_ref,
              current_title: next.title,
              started_at: new Date().toISOString(),
              seek_offset_ms: 0,
              is_playing: true,
            })
            .eq("id", room.id);
          await postBotMessage(admin, room.id, `⏭ Skipped! Now Playing — ${next.title}`);
        } else {
          await admin
            .from("music_rooms")
            .update({
              current_source_type: null,
              current_source_ref: null,
              current_title: null,
              is_playing: false,
              seek_offset_ms: 0,
            })
            .eq("id", room.id);
          await postBotMessage(admin, room.id, "⏭ Skipped. Queue is now empty.");
        }
        return json({ ok: true });
      }

      if (cmd === "!stop") {
        await admin
          .from("music_room_queue")
          .update({ status: "skipped" })
          .eq("room_id", room.id)
          .eq("status", "queued");
        await admin
          .from("music_rooms")
          .update({
            current_source_type: null,
            current_source_ref: null,
            current_title: null,
            is_playing: false,
            seek_offset_ms: 0,
          })
          .eq("id", room.id);
        await postBotMessage(admin, room.id, "⏹ Playback stopped and queue cleared.");
        return json({ ok: true });
      }

      await postBotMessage(admin, room.id, `Unknown command "${cmd}". Type !help for commands.`);
      return json({ ok: true });
    }

    return json({ error: `Unsupported action: ${body.action}` }, 400);
  } catch (err) {
    return json({ error: err instanceof Error ? err.message : String(err) }, 400);
  }
});

async function postBotMessage(
  admin: ReturnType<typeof createClient>,
  roomId: string,
  content: string,
) {
  await admin.from("music_room_messages").insert({
    room_id: roomId,
    display_name: "MusicBot",
    kind: "bot",
    content,
  });
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
