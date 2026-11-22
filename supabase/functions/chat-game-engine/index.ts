import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { generateArithmeticBlitz } from "./math_sequence_generator.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type GameType = "quiz" | "anagram" | "five_letter" | "hangman" | "arithmetic_blitz";

interface EngineRequest {
  action: "start" | "guess" | "hint" | "timeout" | "status" | "change" | "stop" | "results";
  room_id: string;
  game_type?: GameType;
  difficulty?: "easy" | "medium" | "hard";
  guess?: string;
  session_id?: string;
  user_id?: string;
  display_name?: string;
}

const ROUND_DURATION_SECONDS: Record<GameType, number> = {
  quiz: 90,
  anagram: 45,
  five_letter: 120,
  hangman: 90,
  arithmetic_blitz: 30,
};

function normalizeAnswer(input: string): string {
  return input
    .trim()
    .toLowerCase()
    .replace(/[’'`]/g, "'")
    .replace(/\s+/g, " ");
}

function maskHangmanPhrase(phrase: string, revealedLetters: Set<string>): string {
  return phrase
    .toUpperCase()
    .split("")
    .map((ch) => {
      if (!/[A-Z]/.test(ch)) return ch;
      return revealedLetters.has(ch) ? ch : "_";
    })
    .join(" ");
}

function evaluateFiveLetterGuess(guessRaw: string, targetRaw: string) {
  const guess = guessRaw.toUpperCase();
  const target = targetRaw.toUpperCase();
  const statuses: Array<"correct" | "present" | "absent"> = Array(5).fill("absent");
  const remaining: Record<string, number> = {};

  // Pass 1: exact matches
  for (let i = 0; i < 5; i++) {
    if (guess[i] === target[i]) {
      statuses[i] = "correct";
    } else {
      remaining[target[i]] = (remaining[target[i]] ?? 0) + 1;
    }
  }
  // Pass 2: present in wrong position
  for (let i = 0; i < 5; i++) {
    if (statuses[i] === "correct") continue;
    const ch = guess[i];
    if ((remaining[ch] ?? 0) > 0) {
      statuses[i] = "present";
      remaining[ch] -= 1;
    }
  }

  const emoji = statuses
    .map((s) => (s === "correct" ? "🟩" : s === "present" ? "🟨" : "⬜"))
    .join("");

  return { guess, statuses, emoji, solved: guess === target };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const body: EngineRequest = await req.json();
    const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    if (!token) return jsonResponse({error:"Sign in required"},401);
    const {data:{user}} = await supabase.auth.getUser(token);
    if (!user) return jsonResponse({error:"Session expired"},401);
    body.user_id = user.id;
    const { action, room_id } = body;
    const {data: member} = await supabase.from("hotspot_members").select("user_id").eq("hotspot_id",room_id).eq("user_id",user.id).eq("status","active").gt("expires_at",new Date().toISOString()).maybeSingle();
    if (!member) return jsonResponse({error:"Join the room to play"},403);
    const {data:profile}=await supabase.from("user_profiles").select("name").eq("id",user.id).maybeSingle();
    body.display_name = profile?.name || "Player";

    if (!room_id) {
      return jsonResponse({ error: "room_id is required" }, 400);
    }

    // -------------------------------------------------------------------------
    // ACTION: STATUS
    // -------------------------------------------------------------------------
    if (action === "results") {
      const {data,error}=await supabase.rpc("chat_game_period_results",{p_room:room_id});
      if(error) throw error;
      return jsonResponse({results:data});
    }
    if (["start","status","stop","change"].includes(action)) {
      if (body.game_type && !Object.hasOwn(ROUND_DURATION_SECONDS,body.game_type))
        return jsonResponse({error:"Unknown game"},400);
      const {data:series,error}=await supabase.rpc("control_chat_game",{
        p_room:room_id,p_action:action,p_game:body.game_type ?? null
      });
      if(error) throw error;
      if(series.message) return jsonResponse({message:series.message});
      const current = () => supabase.from("room_game_sessions_public").select("*")
        .eq("room_id",room_id).eq("status","active").maybeSingle();
      const {data:existing,error:readError}=await current();
      if(readError) throw readError;
      if(existing || !series.running) return jsonResponse({active_session:existing,outcome:series.outcome});
      const gameType: GameType = series.game_type;
      const expiresAt = new Date(Date.now() + ROUND_DURATION_SECONDS[gameType] * 1000).toISOString();

      let itemId: string | null = null;
      let category = "";
      let difficulty = body.difficulty ?? "medium";
      let secretAnswer = "";
      let acceptedAliases: string[] = [];
      let scReward = 10;
      let publicState: Record<string, unknown> = {};

      if (gameType === "arithmetic_blitz") {
        const gen = generateArithmeticBlitz(body.difficulty);
        itemId = gen.id;
        category = gen.category;
        difficulty = gen.difficulty;
        secretAnswer = gen.answer;
        acceptedAliases = [gen.answer];
        scReward = gen.sc_reward;
        publicState = {
          prompt: gen.prompt,
          hint: null,
          _internal_hint: gen.hint,
        };
      } else {
        // Draw next unseen item using anti-repetition RPC
        const { data: item, error: pickErr } = await supabase.rpc("pick_next_unseen_game_item", {
          p_room_id: room_id,
          p_game_type: gameType,
        });

        if (pickErr || !item || !item.id) {
          return jsonResponse({ error: `No seeded items found for ${gameType}` }, 500);
        }

        itemId = item.id;
        category = item.category;
        difficulty = item.difficulty;
        secretAnswer = item.prompt_payload?.display_answer ?? item.answer_normalized;
        acceptedAliases = Array.isArray(item.accepted_aliases) ? item.accepted_aliases : [item.answer_normalized];
        scReward = item.sc_reward;

        if (gameType === "quiz") {
          publicState = {
            question: item.prompt_payload.question,
            hint: null,
          };
        } else if (gameType === "anagram") {
          publicState = {
            scrambled: item.prompt_payload.scrambled,
            word_length: secretAnswer.length,
            hint: item.prompt_payload.hint,
            revealed_prefix: "",
          };
        } else if (gameType === "five_letter") {
          publicState = {
            word_length: 5,
            max_attempts: 6,
            attempts: [],
          };
        } else if (gameType === "hangman") {
          const revealed = new Set<string>();
          publicState = {
            masked: maskHangmanPhrase(secretAnswer, revealed),
            revealed_letters: [],
            wrong_letters: [],
            max_wrong: 6,
            word_count: item.prompt_payload.word_count,
            letter_count: item.prompt_payload.letter_count,
          };
        }
      }

      const { data: inserted, error: insErr } = await supabase
        .from("room_game_sessions")
        .insert({
          room_id,
          series_generation:series.generation,
          game_type: gameType,
          item_id: itemId,
          category,
          difficulty,
          public_state: publicState,
          secret_answer: secretAnswer,
          accepted_aliases: acceptedAliases,
          started_by: body.user_id ?? null,
          sc_reward: scReward,
          expires_at: expiresAt,
        })
        .select("id")
        .single();

      if (insErr) {
        if(insErr.code==="23505") return jsonResponse({active_session:(await current()).data,outcome:series.outcome});
        return jsonResponse({ error: insErr.message }, 500);
      }

      const { data: safeSession } = await supabase
        .from("room_game_sessions_public")
        .select("*")
        .eq("id", inserted.id)
        .single();

      return jsonResponse({ session:safeSession, active_session:safeSession, outcome:series.outcome },201);
    }

    // -------------------------------------------------------------------------
    // Load active session (with secret_answer on server side only)
    // -------------------------------------------------------------------------
    const { data: active } = await supabase
      .from("room_game_sessions")
      .select("*")
      .eq("room_id", room_id)
      .eq("status", "active")
      .maybeSingle();

    if (!active) {
      return jsonResponse({ active: false, message: "No active game in this room." });
    }

    if (body.session_id && body.session_id !== active.id) return jsonResponse({ignored:true});

    // Check expiration
    if (new Date(active.expires_at).getTime() <= Date.now()) {
      await supabase.from("room_game_sessions").update({ status: "expired" }).eq("id", active.id).eq("status","active");
      return jsonResponse({
        expired: true,
        revealed_answer: active.secret_answer,
        message: `Time's up! The answer was ${active.secret_answer}.`,
      });
    }

    // -------------------------------------------------------------------------
    // ACTION: TIMEOUT
    // -------------------------------------------------------------------------
    if (action === "timeout") return jsonResponse({active:true});

    // -------------------------------------------------------------------------
    // ACTION: HINT (Progressive hint tick)
    // -------------------------------------------------------------------------
    if (action === "hint") {
      const nextStep = (active.hint_step ?? 0) + 1;
      const updatedState = { ...(active.public_state ?? {}) };

      if (active.game_type === "quiz" && active.item_id) {
        const { data: item } = await supabase
          .from("chat_game_items")
          .select("prompt_payload")
          .eq("id", active.item_id)
          .single();
        updatedState.hint = item?.prompt_payload?.hint ?? `Starts with "${active.secret_answer[0]}"`;
      } else if (active.game_type === "anagram") {
        const revealLen = Math.min(nextStep, Math.max(1, Math.floor(active.secret_answer.length / 2)));
        updatedState.revealed_prefix = active.secret_answer.slice(0, revealLen);
      } else if (active.game_type === "hangman") {
        const revealed = new Set<string>(updatedState.revealed_letters ?? []);
        const unrevealed = active.secret_answer
          .toUpperCase()
          .split("")
          .filter((c: string) => /[A-Z]/.test(c) && !revealed.has(c));
        if (unrevealed.length > 1) {
          const revealChar = unrevealed[Math.floor(Math.random() * unrevealed.length)];
          revealed.add(revealChar);
          updatedState.revealed_letters = Array.from(revealed);
          updatedState.masked = maskHangmanPhrase(active.secret_answer, revealed);
        }
      } else if (active.game_type === "arithmetic_blitz") {
        updatedState.hint = updatedState._internal_hint ?? "Double-check order of operations.";
      }

      await supabase
        .from("room_game_sessions")
        .update({ hint_step: nextStep, public_state: updatedState })
        .eq("id", active.id).eq("status","active");

      return jsonResponse({ hint_step: nextStep, public_state: updatedState });
    }

    // -------------------------------------------------------------------------
    // ACTION: GUESS
    // -------------------------------------------------------------------------
    if (action === "guess") {
      if (!body.guess || !body.user_id) {
        return jsonResponse({ error: "guess and user_id are required" }, 400);
      }

      const rawGuess = body.guess.trim();
      const normGuess = normalizeAnswer(rawGuess);
      const displayName = body.display_name ?? "Player";

      // 1. 5-LETTER WORD (Wordle-style feedback)
      if (active.game_type === "five_letter") {
        if (!/^[a-zA-Z]{5}$/.test(rawGuess)) {
          return jsonResponse({ ignored: true, reason: "Not a 5-letter word" });
        }
        const evalResult = evaluateFiveLetterGuess(rawGuess, active.secret_answer);
        const attempts = [...(active.public_state?.attempts ?? [])];
        attempts.push({
          user_id: body.user_id,
          display_name: displayName,
          guess: evalResult.guess,
          statuses: evalResult.statuses,
          emoji: evalResult.emoji,
        });

        const patch = { attempts };

        if (evalResult.solved) {
          const { data: claim, error: claimError } = await supabase.rpc("claim_chat_game_win", {
            p_session_id: active.id,
            p_winner_user_id: body.user_id,
            p_winner_display_name: displayName,
            p_public_state_patch: patch,
          });
          if (claimError) throw claimError;
          if (!claim?.[0]?.claimed) return jsonResponse({ignored:true});
          return jsonResponse({
            solved: true,
            feedback: evalResult,
            claim: claim?.[0] ?? null,
            revealed_answer: active.secret_answer,
          });
        }

        const maxAttempts = active.public_state?.max_attempts ?? 6;
        if (attempts.length >= maxAttempts) {
          await supabase
            .from("room_game_sessions")
            .update({ status: "expired", public_state: { ...active.public_state, ...patch } })
            .eq("id", active.id).eq("status","active");
          return jsonResponse({
            solved: false,
            expired: true,
            feedback: evalResult,
            revealed_answer: active.secret_answer,
          });
        }

        await supabase
          .from("room_game_sessions")
          .update({ public_state: { ...active.public_state, ...patch } })
          .eq("id", active.id).eq("status","active");

        return jsonResponse({ solved: false, feedback: evalResult, attempts_used: attempts.length });
      }

      // 2. HANGMAN / REVEAL (single-letter OR full-phrase guess)
      if (active.game_type === "hangman") {
        const targetUpper = active.secret_answer.toUpperCase();
        const revealed = new Set<string>(active.public_state?.revealed_letters ?? []);
        const wrong = new Set<string>(active.public_state?.wrong_letters ?? []);

        if (normGuess === normalizeAnswer(active.secret_answer)) {
          const allLetters = Array.from(new Set(targetUpper.replace(/[^A-Z]/g, "").split("")));
          const patch = {
            revealed_letters: allLetters,
            masked: maskHangmanPhrase(targetUpper, new Set(allLetters)),
          };
          const { data: claim, error: claimError } = await supabase.rpc("claim_chat_game_win", {
            p_session_id: active.id,
            p_winner_user_id: body.user_id,
            p_winner_display_name: displayName,
            p_public_state_patch: patch,
          });
          if (claimError) throw claimError;
          if (!claim?.[0]?.claimed) return jsonResponse({ignored:true});
          return jsonResponse({ solved: true, claim: claim?.[0] ?? null, revealed_answer: active.secret_answer });
        }

        if (/^[a-zA-Z]$/.test(rawGuess)) {
          const letter = rawGuess.toUpperCase();
          if (revealed.has(letter) || wrong.has(letter)) {
            return jsonResponse({ ignored: true, reason: "Letter already guessed" });
          }
          if (targetUpper.includes(letter)) {
            revealed.add(letter);
          } else {
            wrong.add(letter);
          }
          const masked = maskHangmanPhrase(targetUpper, revealed);
          const patch = {
            revealed_letters: Array.from(revealed),
            wrong_letters: Array.from(wrong),
            masked,
          };

          const fullyUncovered = !masked.includes("_");
          if (fullyUncovered) {
            const { data: claim, error: claimError } = await supabase.rpc("claim_chat_game_win", {
              p_session_id: active.id,
              p_winner_user_id: body.user_id,
              p_winner_display_name: displayName,
              p_public_state_patch: patch,
            });
          if (claimError) throw claimError;
          if (!claim?.[0]?.claimed) return jsonResponse({ignored:true});
            return jsonResponse({ solved: true, claim: claim?.[0] ?? null, revealed_answer: active.secret_answer });
          }

          if (wrong.size >= (active.public_state?.max_wrong ?? 6)) {
            await supabase
              .from("room_game_sessions")
              .update({ status: "expired", public_state: { ...active.public_state, ...patch } })
              .eq("id", active.id).eq("status","active");
            return jsonResponse({ solved: false, expired: true, revealed_answer: active.secret_answer });
          }

          await supabase
            .from("room_game_sessions")
            .update({ public_state: { ...active.public_state, ...patch } })
            .eq("id", active.id).eq("status","active");

          return jsonResponse({ solved: false, letter, hit: targetUpper.includes(letter), masked });
        }

        return jsonResponse({ solved: false, ignored: true });
      }

      // 3. QUIZ, ANAGRAM, ARITHMETIC BLITZ (direct answer match with aliases)
      const aliases: string[] = [
        normalizeAnswer(active.secret_answer),
        ...((active.accepted_aliases as string[]) ?? []).map(normalizeAnswer),
      ];

      if (aliases.includes(normGuess)) {
        const { data: claim, error: claimError } = await supabase.rpc("claim_chat_game_win", {
          p_session_id: active.id,
          p_winner_user_id: body.user_id,
          p_winner_display_name: displayName,
        });
          if (claimError) throw claimError;
          if (!claim?.[0]?.claimed) return jsonResponse({ignored:true});
        return jsonResponse({
          solved: true,
          claim: claim?.[0] ?? null,
          revealed_answer: active.secret_answer,
        });
      }

      return jsonResponse({ solved: false });
    }

    return jsonResponse({ error: `Unsupported action: ${action}` }, 400);
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500);
  }
});

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
