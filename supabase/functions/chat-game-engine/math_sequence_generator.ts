/**
 * Procedural Arithmetic & Sequence Blitz Generator
 * Produces thousands of unique, exact-integer math and sequence puzzles
 * across 8 distinct families so chat rooms never see repetitive rounds.
 */

export interface ArithmeticBlitzItem {
  id: string;
  category: string;
  difficulty: "easy" | "medium" | "hard";
  prompt: string;
  answer: string;
  hint: string;
  sc_reward: number;
}

function randInt(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

export function generateArithmeticBlitz(
  preferredDifficulty?: "easy" | "medium" | "hard",
  recentSignatures: Set<string> = new Set(),
): ArithmeticBlitzItem {
  for (let attempt = 0; attempt < 25; attempt++) {
    const difficulty =
      preferredDifficulty ?? pick<"easy" | "medium" | "hard">(["easy", "medium", "hard"]);
    const item = buildCandidate(difficulty);
    const sig = `${item.prompt}=${item.answer}`;
    if (!recentSignatures.has(sig)) {
      return item;
    }
  }
  return buildCandidate(preferredDifficulty ?? "medium");
}

function buildCandidate(difficulty: "easy" | "medium" | "hard"): ArithmeticBlitzItem {
  const family =
    difficulty === "easy"
      ? pick(["mul_add", "arith_seq", "percent_clean"])
      : difficulty === "medium"
      ? pick(["brackets_mul", "squares_combo", "quad_seq", "percent_clean"])
      : pick(["alt_seq", "fib_shift", "squares_combo", "quad_seq"]);

  const sc_reward = difficulty === "easy" ? 5 : difficulty === "medium" ? 10 : 15;
  const uid = `math_${Date.now().toString(36)}_${randInt(100, 999)}`;

  switch (family) {
    case "mul_add": {
      const a = randInt(6, 19);
      const b = randInt(3, 9);
      const c = randInt(7, 35);
      const add = Math.random() > 0.45;
      const ans = add ? a * b + c : a * b - c;
      const op = add ? "+" : "-";
      return {
        id: uid,
        category: "Mental Math",
        difficulty,
        prompt: `Solve: (${a} × ${b}) ${op} ${c} = ?`,
        answer: String(ans),
        hint: `First compute ${a} × ${b} = ${a * b}.`,
        sc_reward,
      };
    }

    case "brackets_mul": {
      const a = randInt(8, 24);
      const b = randInt(4, 15);
      const c = randInt(3, 9);
      const ans = (a + b) * c;
      return {
        id: uid,
        category: "Mental Math",
        difficulty,
        prompt: `Solve: (${a} + ${b}) × ${c} = ?`,
        answer: String(ans),
        hint: `Inside the brackets equals ${a + b}.`,
        sc_reward,
      };
    }

    case "percent_clean": {
      const pct = pick([10, 15, 20, 25, 30, 40, 50, 75]);
      const base = pick([40, 60, 80, 120, 160, 200, 240, 320, 360, 400, 480]);
      const ans = Math.round((pct * base) / 100);
      return {
        id: uid,
        category: "Percentage Blitz",
        difficulty,
        prompt: `What is ${pct}% of ${base}?`,
        answer: String(ans),
        hint: `10% of ${base} is ${base / 10}.`,
        sc_reward,
      };
    }

    case "squares_combo": {
      const a = randInt(5, 14);
      const b = randInt(3, 11);
      const add = Math.random() > 0.4;
      const ans = add ? a * a + b * b : a * a - b * b;
      const op = add ? "+" : "-";
      return {
        id: uid,
        category: "Powers Blitz",
        difficulty,
        prompt: `Solve: ${a}² ${op} ${b}² = ?`,
        answer: String(ans),
        hint: `${a}² is ${a * a}.`,
        sc_reward,
      };
    }

    case "arith_seq": {
      const start = randInt(3, 25);
      const step = randInt(4, 13);
      const seq = [0, 1, 2, 3].map((i) => start + i * step);
      const ans = start + 4 * step;
      return {
        id: uid,
        category: "Number Sequence",
        difficulty,
        prompt: `Next number: ${seq.join(", ")}, ?`,
        answer: String(ans),
        hint: `Each term increases by a constant step (+${step}).`,
        sc_reward,
      };
    }

    case "quad_seq": {
      const start = randInt(1, 10);
      const d1 = randInt(2, 6);
      const inc = randInt(2, 5);
      const seq: number[] = [start];
      for (let i = 0; i < 4; i++) {
        seq.push(seq[seq.length - 1] + d1 + i * inc);
      }
      const ans = seq.pop()!;
      return {
        id: uid,
        category: "Number Sequence",
        difficulty,
        prompt: `Next number: ${seq.join(", ")}, ?`,
        answer: String(ans),
        hint: `The gap between terms grows by +${inc} each step.`,
        sc_reward,
      };
    }

    case "alt_seq": {
      const start = randInt(2, 7);
      const mult = pick([2, 3]);
      const add = randInt(2, 6);
      const seq: number[] = [start];
      for (let i = 0; i < 5; i++) {
        const prev = seq[seq.length - 1];
        seq.push(i % 2 === 0 ? prev * mult : prev + add);
      }
      const ans = seq.pop()!;
      return {
        id: uid,
        category: "Logic Sequence",
        difficulty,
        prompt: `Next number: ${seq.join(", ")}, ?`,
        answer: String(ans),
        hint: `Pattern alternates between ×${mult} and +${add}.`,
        sc_reward,
      };
    }

    case "fib_shift":
    default: {
      const a = randInt(2, 8);
      const b = randInt(3, 10);
      const seq = [a, b, a + b, a + 2 * b, 2 * a + 3 * b];
      const ans = seq[3] + seq[4];
      return {
        id: uid,
        category: "Logic Sequence",
        difficulty,
        prompt: `Next number: ${seq.join(", ")}, ?`,
        answer: String(ans),
        hint: `Each term is the sum of the two terms before it.`,
        sc_reward,
      };
    }
  }
}
