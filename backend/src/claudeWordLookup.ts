interface ClaudeContentBlock {
  type: string;
  text?: string;
}

interface ClaudeResponse {
  content: ClaudeContentBlock[];
}

interface WordLookupResult {
  translation: string;
  partOfSpeech: string | null;
}

const SYSTEM_PROMPT = `You translate a single English word into Russian, using the
given sentence to pick the correct sense (e.g. "bank" -> "берег" vs "банк").
Always provide a translation, even for names, numerals, abbreviations, or
single letters — transliterate or describe briefly if there's no direct
Russian equivalent, but the "translation" field must never be empty.
Respond with ONLY a JSON object, no markdown fences, no preamble:
{"translation": "<russian word or short phrase>", "partOfSpeech": "<noun|verb|adjective|adverb|other>"}`;

export async function lookupWordWithClaude(
  word: string,
  contextSentence: string,
  apiKey: string
): Promise<WordLookupResult> {
  // One retry: Claude occasionally declines to fill "translation" for edge
  // cases (a bare Roman numeral, a single letter, an abbreviation) despite
  // the system prompt insisting it's required — a second attempt, with an
  // extra reminder appended, resolves most of these without the user ever
  // seeing an error. Only retried once to keep worst-case latency bounded.
  const result = await attemptLookup(word, contextSentence, apiKey, false);
  if (result) return result;

  const retryResult = await attemptLookup(word, contextSentence, apiKey, true);
  if (retryResult) return retryResult;

  throw new Error(`Claude did not return a usable translation for "${word}" after retry`);
}

async function attemptLookup(
  word: string,
  contextSentence: string,
  apiKey: string,
  isRetry: boolean
): Promise<WordLookupResult | null> {
  const userContent = isRetry
    ? `Word: "${word}"\nSentence: "${contextSentence}"\n(Your previous response was missing or malformed — respond with ONLY the JSON object, and "translation" must be a non-empty string.)`
    : `Word: "${word}"\nSentence: "${contextSentence}"`;

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001", // fast + cheap — plenty for single-word lookups
      max_tokens: 100,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userContent }],
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Claude API error ${response.status}: ${body}`);
  }

  const data = (await response.json()) as ClaudeResponse;
  const text = data.content.find((block) => block.type === "text")?.text;
  if (!text) return null;

  // The system prompt asks for raw JSON, but models occasionally wrap it in
  // ```json fences anyway — strip those defensively rather than letting the
  // whole request fail on an otherwise-valid response.
  const cleaned = text.trim().replace(/^```(?:json)?\s*/i, "").replace(/```\s*$/i, "").trim();

  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    return null;
  }

  // Valid JSON isn't the same as *usable* JSON — explicitly check the shape
  // rather than trusting `parsed.translation` to be there just because
  // parsing succeeded. A missing/empty translation used to slip through
  // here as `undefined`, which JSON.stringify silently drops from the
  // response, and the client's decoder then failed on the missing field —
  // which is exactly the "same word always fails" symptom this fixes.
  if (
    typeof parsed !== "object" ||
    parsed === null ||
    typeof (parsed as { translation?: unknown }).translation !== "string" ||
    (parsed as { translation: string }).translation.trim().length === 0
  ) {
    return null;
  }

  const partOfSpeechValue = (parsed as { partOfSpeech?: unknown }).partOfSpeech;
  return {
    translation: (parsed as { translation: string }).translation,
    partOfSpeech: typeof partOfSpeechValue === "string" ? partOfSpeechValue : null,
  };
}
