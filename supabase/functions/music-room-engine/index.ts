import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Spotmate Music Room Edge Function (`music-room-engine`)
 * - Free Rooms: 0 SC, 30 min cap, max 5 members, empty-room auto-close + next-batch allocation.
 * - Custom Rooms: 5 SC (30 min) or 10 SC (60 min), Room Code + Spotmate ID/User ID invites.
 * - Room member commands in Chat: !play, !pause, !resume, !skip, !queue, !np, !stop, !help.
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
    | "room.transfer_host"

    | "room.change_tv"
    | "room.sync_state"
    | "chat.send";
  room_kind?: "music" | "tv";
  video_id?: string;
  room_id?: string;
  room_code?: string;
  next_host_id?: string;
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
    const roomKind = body.room_kind === "tv" ? "tv" : "music";
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
        .eq("room_kind", roomKind)
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
    if (body.action === "room.create_free" && roomKind === "tv") {
      const { data: room, error } = await admin.rpc("create_tv_room", {
        p_host: userId, p_title: (body.title ?? displayName + "'s TV Room").trim(),
        p_name: displayName, p_avatar: body.avatar_url ?? null, p_duration: 30, p_custom: false,
      });
      if (error) return json({error: error.message}, 400);
      return json({room, server_now_ms: Date.now()}, 201);
    }
    if (body.action === "room.create_free") {
      const {data:room,error}=await admin.rpc("create_free_listening_room",{
        p_host:userId,p_title:(body.title ?? displayName+"'s Free Lounge").trim(),
        p_name:displayName,p_avatar:body.avatar_url ?? null
      });
      if(error) return json({error:error.message},400);
      await postBotMessage(
        admin,
        room.id,
        `Free 30-min Music Room started (max 5 seats). Anyone in the room can type !play <song or YouTube link> to start!`,
      );
      return json({ room, server_now_ms: Date.now() }, 201);
    }

    // -------------------------------------------------------------------------
    // 3. CREATE CUSTOM ROOM (30 min = 5 SC, 60 min = 10 SC)
    // -------------------------------------------------------------------------
    if (body.action === "room.create_custom" && roomKind === "tv") {
      const { data: room, error } = await admin.rpc("create_tv_room", {
        p_host: userId, p_title: body.title ?? displayName + "'s TV Room",
        p_name: displayName, p_avatar: body.avatar_url ?? null,
        p_duration: body.duration_minutes === 60 ? 60 : 30, p_custom: true,
      });
      if (error) return json({error: error.message}, 400);
      return json({room, server_now_ms: Date.now()}, 201);
    }
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
    if (body.action === "room.join" && body.room_id) {
      const {data:room}=await admin.from("music_rooms").select("mode,room_kind").eq("id",body.room_id).maybeSingle();
      if (room?.room_kind !== roomKind) return json({error:"Room not found"},404);
      if (room?.mode==="custom") return json({error:"Enter the room code"},403);
    }
    if (body.action === "room.join" || body.action === "room.join_by_code") {
      let targetRoomId = body.room_id;
      if (body.action === "room.join_by_code") {
        const code = (body.room_code ?? "").trim().toUpperCase();
        const { data: found } = await admin
          .from("music_rooms")
          .select("id")
          .eq("room_code", code)
          .eq("room_kind", roomKind)
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
    if(body.action==="room.transfer_host"){
      const {error}=await admin.rpc("transfer_free_music_host",{p_room:body.room_id,p_actor:userId,p_next:body.next_host_id});
      return error?json({error:error.message},403):json({ok:true});
    }
    if (body.action === "room.leave") {
      const {data: targetRoom, error: lookupError} = await admin.from("music_rooms")
        .select("room_kind").eq("id", body.room_id).maybeSingle();
      if (lookupError) return json({error: lookupError.message}, 400);
      if (targetRoom?.room_kind === "tv") {
        const {error} = await admin.rpc("tv_room_leave", {p_room: body.room_id, p_user: userId});
        return error ? json({error: error.message}, 400) : json({ok:true});
      }
      if (!body.room_id) return json({ error: "room_id is required" }, 400);
      const { data: res,error } = await admin.rpc("music_leave_and_reallocate", {
        p_room_id: body.room_id,
        p_user_id: userId,
      });
      return error?json({error:error.message},400):json({result:res});
    }

    // -------------------------------------------------------------------------
    // 7. INVITE FRIEND TO CUSTOM ROOM BY SPOTMATE ID OR USER ID
    // -------------------------------------------------------------------------


    // -------------------------------------------------------------------------
    // 8. SYNC STATE (Returns room, members, queue, and exact server_now_ms)
    // -------------------------------------------------------------------------
    if (body.action === "room.change_tv") {
      if (!body.room_id || !body.video_id || !/^[A-Za-z0-9_-]{11}$/.test(body.video_id))
        return json({error:"Choose a live channel"}, 400);
      const {data:member} = await admin.from("music_room_members").select("user_id")
        .eq("room_id", body.room_id).eq("user_id", userId).maybeSingle();
      if (!member) return json({error:"Join this room first"},403);
      const key = Deno.env.get("YOUTUBE_API_KEY");
      if (!key) return json({error:"YouTube is not configured"},503);
      const params = new URLSearchParams({part:"snippet,status,liveStreamingDetails",id:body.video_id,key});
      const response = await fetch("https://www.googleapis.com/youtube/v3/videos?" + params);
      if (!response.ok) return json({error:"Could not verify the live channel"},502);
      const item = (await response.json()).items?.[0];
      if (!item || item.snippet?.liveBroadcastContent !== "live" || item.status?.embeddable !== true)
        return json({error:"This broadcast is no longer available live"},400);
      const {error} = await admin.rpc("tv_room_change_channel", {
        p_room:body.room_id,p_user:userId,p_video_id:body.video_id,p_title:(item.snippet.title ?? "Live TV").slice(0,300),
      });
      return error ? json({error:error.message},400) : json({ok:true});
    }
    if (["room.sync_state","chat.send"].includes(body.action)) {
      const {data:member}=await admin.from("music_room_members").select("user_id").eq("room_id",body.room_id).eq("user_id",userId).maybeSingle();
      if (!member) return json({error:"Join this room first"},403);
    }
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

      const { data: member, error: memberError } = await admin
        .from("music_room_members").select("user_id")
        .eq("room_id", room.id).eq("user_id", userId).maybeSingle();
      if (memberError) throw memberError;
      if (!member) return json({ error: "Join the room to send messages." }, 403);

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
          "Commands: !play <song or YouTube link>, !pause, !resume, !skip, !queue, !np, !stop",
        );
        return json({ ok: true });
      }

      if (cmd === "!np") {
        const text = room.current_title
          ? `🎵 Now Playing: ${room.current_title} (${room.is_playing ? "Playing" : "Paused"})`
          : "Nothing is playing right now. Type !play <song>.";
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

      if (room.room_kind === "tv" && ["!play", "!pause", "!resume", "!skip", "!stop"].includes(cmd)) {
        return json({error:"Choose a live channel using the Channels button."},400);
      }
      if (["!play", "!pause", "!resume", "!skip", "!stop"].includes(cmd)) {
        let track = null;
        if (cmd === "!play") {
          if (!arg) {
            await postBotMessage(admin, room.id, "Usage: !play <YouTube URL or song name>");
            return json({ ok: true });
          }
          track = await resolvePlayableTrack(arg);
          if (!track) {
            await postBotMessage(admin, room.id, "Song search is unavailable. Try a YouTube video link.");
            return json({ ok: true });
          }
        }
        const { data: result, error } = await admin.rpc("music_member_control", {
          p_room: room.id, p_user: userId, p_action: cmd.slice(1),
          p_source_type: track?.source_type ?? null,
          p_source_ref: track?.source_ref ?? null,
          p_title: track?.title ?? null,
        });
        if (error) return json({ error: error.message }, 400);
        await postBotMessage(admin, room.id, result);
        return json({ ok: true, server_now_ms: Date.now() });
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
