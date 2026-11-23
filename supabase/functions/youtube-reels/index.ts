import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
type Reel = { id: string; youtube_video_id: string; title: string; creator_handle: string; city_tag: string; thumbnail_url: string; likes_count: number; shares_count: number };
const cache = new Map<string, { expires: number; reels: Reel[] }>();
const topics = ["food", "travel", "comedy", "music", "nature", "technology", "sports", "art", "animals", "interesting facts"];
function shuffle<T>(items: T[]): T[] {
  const result = [...items];
  for (let i = result.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}
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
    const topic = topics[Math.floor(Math.random() * topics.length)];
    const query = tab === "city" && city ? `${city} ${topic} shorts` : `${topic} shorts`;
    const cacheKey = `${tab}:${query}`;
    let reels = cache.get(cacheKey);
    if (!reels || reels.expires <= Date.now()) {
      const key = Deno.env.get("YOUTUBE_API_KEY");
      if (!key) return new Response(JSON.stringify({ error: "YouTube search needs to be configured." }), { status: 503, headers });
      const params = new URLSearchParams({part: "snippet", type: "video", videoEmbeddable: "true", videoDuration: "short", maxResults: "50", q: query, order: tab === "trending" ? "viewCount" : "relevance", key});
      const response = await fetch(`https://www.googleapis.com/youtube/v3/search?${params}`);
      if (!response.ok) return new Response(JSON.stringify({ error: "YouTube search is unavailable. Try again later." }), { status: 502, headers });
      const result = await response.json();
      const unique = new Map<string, Reel>();
      for (const item of result.items ?? []) {
        const id = item.id?.videoId;
        if (typeof id !== "string" || !/^[A-Za-z0-9_-]{11}$/.test(id)) continue;
        unique.set(id, {id, youtube_video_id: id, title: item.snippet?.title ?? "YouTube video", creator_handle: item.snippet?.channelTitle ?? "YouTube", city_tag: "", thumbnail_url: item.snippet?.thumbnails?.high?.url ?? item.snippet?.thumbnails?.default?.url ?? `https://i.ytimg.com/vi/${id}/hqdefault.jpg`, likes_count: 0, shares_count: 0});
      }
      reels = {expires: Date.now() + 10 * 60 * 1000, reels: [...unique.values()]};
      cache.set(cacheKey, reels);
    }
    const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const {data: watched, error} = await client.from("youtube_reel_views").select("video_id,viewed_at").eq("user_id", data.user.id).gte("viewed_at", cutoff).order("viewed_at", {ascending: false}).limit(5000);
    if (error) console.error("Reel history unavailable", error.code);
    const seen = new Map((watched ?? []).map((row) => [row.video_id, row.viewed_at]));
    const shuffled = shuffle(reels.reels);
    const fresh = shuffled.filter((reel) => !seen.has(reel.id));
    // If the available results are exhausted, show the least recently watched last.
    const old = shuffled.filter((reel) => seen.has(reel.id)).sort((a, b) => String(seen.get(a.id)).localeCompare(String(seen.get(b.id))));
    return new Response(JSON.stringify({reels: [...fresh, ...old]}), {headers});
  } catch {
    return new Response(JSON.stringify({error: "Could not load YouTube videos."}), {status: 400, headers});
  }
});
