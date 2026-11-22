import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface LiveTvRequest {
  action: "channels.list" | "channel.ping" | "chat.send" | "admin.upsert_channel";
  category?: string;
  language?: string;
  search?: string;
  channel_id?: string;
  display_name?: string;
  avatar_url?: string;
  body?: string;
  reaction_emoji?: string;
  name?: string;
  stream_type?: "youtube_live" | "youtube_channel" | "hls";
  stream_source?: string;
  logo_url?: string;
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
    const body = (await req.json()) as LiveTvRequest;

    if (body.action === "channels.list") {
      let query = adminClient
        .from("spotmate_live_channels")
        .select("*")
        .eq("is_live", true)
        .order("sort_order", { ascending: true })
        .order("viewer_count", { ascending: false });

      if (body.category && body.category !== "All") {
        query = query.eq("category", body.category);
      }
      if (body.language && body.language !== "All") {
        query = query.eq("language", body.language);
      }
      if (body.search && body.search.trim().length > 0) {
        query = query.ilike("name", `%${body.search.trim()}%`);
      }

      const { data, error } = await query;
      if (error) throw error;
      return new Response(JSON.stringify({ channels: data ?? [] }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (body.action === "channel.ping") {
      if (!body.channel_id) throw new Error("channel_id is required");
      const { data, error } = await userClient.rpc("ping_live_tv_viewer", {
        p_channel_id: body.channel_id,
      });
      if (error) throw error;
      return new Response(JSON.stringify({ viewer_count: data ?? 1 }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (body.action === "chat.send") {
      if (!body.channel_id) throw new Error("channel_id is required");
      const text = (body.body ?? "").trim();
      const emoji = (body.reaction_emoji ?? "").trim();
      if (!text && !emoji) throw new Error("Message or reaction_emoji is required");

      const { data, error } = await adminClient
        .from("spotmate_live_tv_messages")
        .insert({
          channel_id: body.channel_id,
          user_id: uid,
          display_name: body.display_name ?? "Spotmate User",
          avatar_url: body.avatar_url ?? null,
          body: text || null,
          reaction_emoji: emoji || null,
        })
        .select("*")
        .single();
      if (error) throw error;
      return new Response(JSON.stringify({ message: data }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (body.action === "admin.upsert_channel") {
      if (userData.user.app_metadata?.admin !== true) return new Response(JSON.stringify({error:'Admin access required'}),{status:403,headers:corsHeaders});

      if (!body.name || !body.stream_source) {
        throw new Error("name and stream_source are required");
      }
      const { data, error } = await adminClient
        .from("spotmate_live_channels")
        .insert({
          name: body.name,
          category: body.category ?? "News",
          language: body.language ?? "Telugu",
          stream_type: body.stream_type ?? "youtube_live",
          stream_source: body.stream_source,
          logo_url: body.logo_url ?? null,
          is_live: true,
        })
        .select("*")
        .single();
      if (error) throw error;
      return new Response(JSON.stringify({ channel: data }), {
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
