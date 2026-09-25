interface DeepLResponse {
  translations: { text: string; detected_source_language: string }[];
}

/// Free and Pro DeepL accounts use different API hosts — free keys end in ":fx".
function deeplHost(apiKey: string): string {
  return apiKey.endsWith(":fx") ? "api-free.deepl.com" : "api.deepl.com";
}

export async function translateSentenceWithDeepL(
  sentence: string,
  targetLang: string,
  apiKey: string
): Promise<string> {
  const response = await fetch(`https://${deeplHost(apiKey)}/v2/translate`, {
    method: "POST",
    headers: {
      "Authorization": `DeepL-Auth-Key ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text: [sentence],
      target_lang: targetLang.toUpperCase(), // e.g. "RU"
      source_lang: "EN",
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`DeepL error ${response.status}: ${body}`);
  }

  const data = (await response.json()) as DeepLResponse;
  const translated = data.translations[0]?.text;
  if (!translated) {
    throw new Error("DeepL returned no translation");
  }
  return translated;
}
