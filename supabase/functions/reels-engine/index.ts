import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ReelsRequest {
  action: "feed.list" | "reel.toggle_like" | "reel.share" | "admin.add_short";
  tab?: "for_you" | "city" | "trending";
  city_tag?: string;
  initial_reel_id?: string;
  limit?: number;
  offset?: number;
  reel_id?: string;
  recipient_id?: string;
  chat_thread_id?: string;
  note?: string;
  youtube_url?: string;
  title?: string;
  creator_handle?: string;
  category?: string;
}

function extractYouTubeVideoId(input: string): string | null {
  const trimmed = input.trim();
  if (/^[a-zA-Z0-9_-]{11}$/.test(trimmed)) return trimmed;
  const patterns = [
    /youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})/,
    /youtu\.be\/([a-zA-Z0-9_-]{11})/,
    /youtube\.com\/watch\?v=([a-zA-Z0-9_-]{11})/,
    /youtube\.com\/embed\/([a-zA-Z0-9_-]{11})/,
  ];
  for (const re of patterns) {
    const m = trimmed.match(re);
    if (m?.[1]) return m[1];
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const adminClient = createClient(supabaseUrl, serviceKey);

    const { data: userData, error: userErr } = await userClient.auth.getUser();
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const uid = userData.user.id;
    const body = (await req.json()) as ReelsRequest;

    if (body.action === "feed.list") {
      const limit = Math.min(Math.max(body.limit ?? 20, 1), 50);
      const offset = Math.max(body.offset ?? 0, 0);

      let query = adminClient
        .from("spotmate_reels")
        .select("*")
        .eq("is_active", true);

      if (body.tab === "city" && body.city_tag) {
        query = query.eq("city_tag", body.city_tag);
      }
      if (body.tab === "trending") {
        query = query.order("shares_count", { ascending: false }).order("likes_count", { ascending: false });
      } else {
        query = query.order("sort_order", { ascending: true }).order("created_at", { ascending: false });
      }

      const { data: rows, error } = await query.range(offset, offset + limit - 1);
      if (error) throw error;

      let reels = rows ?? [];

      // Pin deep-linked reel at index 0 when opened from a Private Chat card
      if (body.initial_reel_id && offset === 0) {
        const existingIdx = reels.findIndex((r) => r.id === body.initial_reel_id);
        if (existingIdx > 0) {
          const [pinned] = reels.splice(existingIdx, 1);
          reels = [pinned, ...reels];
        } else if (existingIdx === -1) {
          const { data: single } = await adminClient
            .from("spotmate_reels")
            .select("*")
            .eq("id", body.initial_reel_id)
            .maybeSingle();
          if (single) {
            reels = [single, ...reels];
          }
        }
      }

      const reelIds = reels.map((r) => r.id);
      const likedSet = new Set<string>();
      if (reelIds.length > 0) {
        const { data: likes } = await adminClient
          .from("spotmate_reel_likes")
          .select("reel_id")
          .eq("user_id", uid)
          .in("reel_id", reelIds);
        for (const l of likes ?? []) likedSet.add(l.reel_id);
      }

      const enriched = reels.map((r) => ({
        ...r,
        liked_by_me: likedSet.has(r.id),
      }));

      return new Response(JSON.stringify({ reels: enriched }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (body.action === "reel.toggle_like") {
      if (!body.reel_id) throw new Error("reel_id is required");
      const { data, error } = await userClient.rpc("toggle_spotmate_reel_like", {
        p_reel_id: body.reel_id,
      });
      if (error) throw error;
      return new Response(JSON.stringify(data), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (body.action === "reel.share") {
      if (!body.reel_id || !body.recipient_id) {
        throw new Error("reel_id and recipient_id are required");
      }
      const { data, error } = await userClient.rpc("record_spotmate_reel_share", {
        p_reel_id: body.reel_id,
        p_recipient_id: body.recipient_id,
        p_chat_thread_id: body.chat_thread_id ?? null,
        p_note: body.note ?? null,
      });
      if (error) throw error;
      return new Response(JSON.stringify({ payload: data }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (body.action === "admin.add_short") {
      if (userData.user.app_metadata?.admin !== true) return new Response(JSON.stringify({error:'Admin access required'}),{status:403,headers:corsHeaders});

      const videoId = extractYouTubeVideoId(body.youtube_url ?? "");
      if (!videoId) throw new Error("Invalid YouTube Shorts URL or video ID");
      const { data, error } = await adminClient
        .from("spotmate_reels")
        .upsert(
          {
            youtube_video_id: videoId,
            title: body.title ?? "Spotmate Reel",
            creator_handle: body.creator_handle ?? "@spotmate",
            city_tag: body.city_tag ?? "Hyderabad",
            category: body.category ?? "trending",
            is_active: true,
          },
          { onConflict: "youtube_video_id" }
        )
        .select("*")
        .single();
      if (error) throw error;
      return new Response(JSON.stringify({ reel: data }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
