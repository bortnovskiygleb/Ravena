import { translateSentenceWithDeepL } from "./deepl";
import { lookupWordWithClaude } from "./claudeWordLookup";

export interface Env {
  DEEPL_API_KEY: string;
  ANTHROPIC_API_KEY: string;
  APP_AUTH_TOKEN: string; // shared secret the iOS app sends — NOT a provider key
}

const MAX_WORD_LENGTH = 100;
const MAX_SENTENCE_LENGTH = 2000;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// Comparing the Authorization header with plain `===` leaks timing
/// information character-by-character (the comparison short-circuits at the
/// first mismatched byte), which in principle lets an attacker recover the
/// token faster than brute force by measuring response latency. Hashing both
/// sides first normalizes the comparison to a fixed-length, fixed-time op —
/// the standard mitigation for this class of side-channel.
async function isAuthorized(request: Request, env: Env): Promise<boolean> {
  const header = request.headers.get("Authorization") ?? "";
  const expected = `Bearer ${env.APP_AUTH_TOKEN}`;
  return timingSafeEqual(header, expected);
}

async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [hashA, hashB] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(a)),
    crypto.subtle.digest("SHA-256", encoder.encode(b)),
  ]);
  const bytesA = new Uint8Array(hashA);
  const bytesB = new Uint8Array(hashB);
  let diff = 0;
  for (let i = 0; i < bytesA.length; i++) {
    diff |= bytesA[i] ^ bytesB[i];
  }
  return diff === 0;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    // Simple shared-secret check. This stops random internet traffic from
    // burning through your DeepL/Claude quota — it is NOT full user auth.
    // For a real multi-user app, swap this for a per-device or per-account token.
    if (!(await isAuthorized(request, env))) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const url = new URL(request.url);

    try {
      if (url.pathname === "/translate/sentence") {
        const { sentence, targetLanguage } = await request.json<{
          sentence: string;
          targetLanguage: string;
        }>();

        if (!sentence) {
          return jsonResponse({ error: "Missing 'sentence'" }, 400);
        }
        if (sentence.length > MAX_SENTENCE_LENGTH) {
          return jsonResponse({ error: "'sentence' is too long" }, 400);
        }

        const translated = await translateSentenceWithDeepL(
          sentence,
          targetLanguage ?? "ru",
          env.DEEPL_API_KEY
        );
        return jsonResponse({ translated });
      }

      if (url.pathname === "/translate/word") {
        const { word, contextSentence } = await request.json<{
          word: string;
          contextSentence: string;
        }>();

        if (!word || !contextSentence) {
          return jsonResponse({ error: "Missing 'word' or 'contextSentence'" }, 400);
        }
        if (word.length > MAX_WORD_LENGTH || contextSentence.length > MAX_SENTENCE_LENGTH) {
          return jsonResponse({ error: "Input too long" }, 400);
        }

        const result = await lookupWordWithClaude(word, contextSentence, env.ANTHROPIC_API_KEY);
        return jsonResponse({
          translation: result.translation,
          partOfSpeech: result.partOfSpeech,
        });
      }

      return jsonResponse({ error: "Not found" }, 404);
    } catch (error) {
      // Deliberately not returning `String(error)` to the client — upstream
      // error bodies can contain account/plan details from DeepL or Anthropic
      // that shouldn't be exposed to anyone holding just the shared app token.
      console.error("Translation request failed:", error);
      return jsonResponse({ error: "Translation failed. Please try again." }, 502);
    }
  },
};
