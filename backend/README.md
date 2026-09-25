# Backend: reader-translate-proxy

A Cloudflare Workers proxy. It stores DeepL and Anthropic keys on the server so the iOS app only communicates with it.

## Deployment

```bash
npm install -g wrangler
cd backend
npm init -y
npm install --save-dev @cloudflare/workers-types typescript

# Secrets (prompts interactively, not stored in git)
npx wrangler secret put DEEPL_API_KEY
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put APP_AUTH_TOKEN   # generate your own long random string

npx wrangler deploy
```

After deployment, you will get a URL like `https://reader-translate-proxy.<your-subdomain>.workers.dev` — this is the `baseURL` for the `APITranslationService` in the iOS app.

## How to Get Keys

- **DeepL**: https://www.deepl.com/pro-api — free tier provides ~500k chars/month.
- **Anthropic**: https://console.anthropic.com — create an API key in the console.

## Endpoints

### POST /translate/sentence
```json
{ "sentence": "The cat sat on the mat.", "targetLanguage": "ru" }
```
→ `{ "translated": "Кот сидел на коврике." }`

### POST /translate/word
```json
{ "word": "bank", "contextSentence": "We sat by the river bank." }
```
→ `{ "translation": "берег", "partOfSpeech": "noun" }`

Both require the header: `Authorization: Bearer <APP_AUTH_TOKEN>`.

## Current Version Limitations (intentional, for MVP)

- Authorization — one shared secret for the entire app, not a per-user token. Good enough for a single client (testing) or closed beta. For public release, replace with per-device/per-account tokens (otherwise, a leaked binary secret allows anyone to spend your DeepL/Anthropic budget).
- No user-level rate limiting — on the free tier, Workers limits to 100k requests/day per Worker, but this protects infrastructure, not the budget from a malicious client.
- No server-side caching — caching is currently in-memory on the client (see CachingTranslationService.swift), tied to the session lifecycle.
