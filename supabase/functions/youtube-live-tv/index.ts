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
  if (!data.user) return new Response(JSON.stringify({ error: "Sign in to view Live TV." }), { status: 401, headers });

  try {
    const body = await req.json();
    const category = typeof body.category === "string" ? body.category.slice(0, 30).trim() : "";
    const language = typeof body.language === "string" ? body.language.slice(0, 30).trim() : "";
    const search = typeof body.search === "string" ? body.search.slice(0, 80).trim() : "";
    const query = [search, category == "All" ? "" : category, language == "All" ? "" : language, "live"].filter(Boolean).join(" ");
    const cacheKey = query.toLowerCase();
    const previous = cache.get(cacheKey);
    if (previous && previous.expires > Date.now()) return new Response(JSON.stringify({ reels: previous.reels }), { headers });

    const key = Deno.env.get("YOUTUBE_API_KEY");
    if (!key) return new Response(JSON.stringify({ error: "YouTube search needs to be configured." }), { status: 503, headers });
    const params = new URLSearchParams({
      part: "snippet", type: "video", videoEmbeddable: "true",
      eventType: "live", maxResults: "30", q: query, order: "relevance", key,
    });
    const response = await fetch(`https://www.googleapis.com/youtube/v3/search?${params}`);
    if (!response.ok) return new Response(JSON.stringify({ error: "YouTube search is unavailable. Try again later." }), { status: 502, headers });
    const result = await response.json();
    const reels = (result.items ?? []).filter((item: any) => item.id?.videoId).map((item: any) => ({
      id: item.id.videoId,
      name: item.snippet?.title ?? "YouTube Live",
      creator: item.snippet?.channelTitle ?? "YouTube",
      thumbnail: item.snippet?.thumbnails?.high?.url ?? item.snippet?.thumbnails?.default?.url,
    }));
    cache.set(cacheKey, { expires: Date.now() + 10 * 60 * 1000, reels });
    return new Response(JSON.stringify({ reels }), { headers });
  } catch {
    return new Response(JSON.stringify({ error: "Could not load YouTube Live." }), { status: 400, headers });
  }
});
