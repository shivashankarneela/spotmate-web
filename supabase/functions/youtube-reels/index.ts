import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};
const cache = new Map<string, { expires: number; reels: unknown[] }>();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  const client = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data } = await client.auth.getUser();
  if (!data.user) return new Response(JSON.stringify({ error: "Sign in to view reels." }), { status: 401, headers });

  try {
    const body = await req.json();
    const tab = ["for_you", "city", "trending"].includes(body.tab) ? body.tab : "for_you";
    const city = typeof body.city_tag === "string" ? body.city_tag.slice(0, 60).trim() : "";
    const query = tab === "city" && city ? `${city} shorts` : "shorts";
    const cacheKey = `${tab}:${city}`;
    const previous = cache.get(cacheKey);
    if (previous && previous.expires > Date.now()) return new Response(JSON.stringify({ reels: previous.reels }), { headers });

    const key = Deno.env.get("YOUTUBE_API_KEY");
    if (!key) return new Response(JSON.stringify({ error: "YouTube search needs to be configured." }), { status: 503, headers });
    const params = new URLSearchParams({
      part: "snippet", type: "video", videoEmbeddable: "true",
      videoDuration: "short", maxResults: "40", q: query,
      order: tab === "trending" ? "viewCount" : "relevance", key,
    });
    const response = await fetch(`https://www.googleapis.com/youtube/v3/search?${params}`);
    if (!response.ok) return new Response(JSON.stringify({ error: "YouTube search is unavailable. Try again later." }), { status: 502, headers });
    const result = await response.json();
    const reels = (result.items ?? []).filter((item: any) => item.id?.videoId).map((item: any) => ({
      id: item.id.videoId,
      youtube_video_id: item.id.videoId,
      title: item.snippet?.title ?? "YouTube video",
      creator_handle: item.snippet?.channelTitle ?? "YouTube",
      city_tag: "",
      thumbnail_url: item.snippet?.thumbnails?.high?.url ?? item.snippet?.thumbnails?.default?.url,
      likes_count: 0,
      shares_count: 0,
    }));
    cache.set(cacheKey, { expires: Date.now() + 10 * 60 * 1000, reels });
    return new Response(JSON.stringify({ reels }), { headers });
  } catch {
    return new Response(JSON.stringify({ error: "Could not load YouTube videos." }), { status: 400, headers });
  }
});
