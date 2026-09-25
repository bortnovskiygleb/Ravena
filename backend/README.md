# Backend: reader-translate-proxy

Прокси на Cloudflare Workers. Держит ключи DeepL и Anthropic на сервере,
iOS-приложение обращается только сюда.

## Деплой

```bash
npm install -g wrangler
cd backend
npm init -y
npm install --save-dev @cloudflare/workers-types typescript

# Секреты (спросит значение интерактивно, в git не попадают)
npx wrangler secret put DEEPL_API_KEY
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put APP_AUTH_TOKEN   # придумайте свою длинную случайную строку

npx wrangler deploy
```

После деплоя вы получите URL вида `https://reader-translate-proxy.<ваш-субдомен>.workers.dev` —
это и есть `baseURL` для `APITranslationService` в iOS-приложении.

## Как получить ключи

- **DeepL**: https://www.deepl.com/pro-api — бесплатный тариф даёт ~500k символов/месяц.
- **Anthropic**: https://console.anthropic.com — создать API key в консоли.

## Эндпоинты

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

Оба требуют заголовок `Authorization: Bearer <APP_AUTH_TOKEN>`.

## Ограничения текущей версии (сознательно, для MVP)

- Авторизация — один общий секрет на всё приложение, а не per-user токен.
  Годится, пока у вас один клиент (сами тестируете) или закрытая бета.
  Для публичного релиза нужно заменить на per-device/per-account токены
  (иначе один "утёкший" секрет из бинарника позволит кому угодно тратить
  ваш DeepL/Anthropic бюджет).
- Нет rate-limiting на уровне пользователя — на бесплатном тарифе Workers
  сам ограничивает 100k запросов/день на весь Worker, но это защита
  инфраструктуры, а не защита бюджета от одного недобросовестного клиента.
- Нет кеширования на сервере — кеш сейчас только in-memory на клиенте
  (см. CachingTranslationService.swift), живёт только в рамках сессии.
