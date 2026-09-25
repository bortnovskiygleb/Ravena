# Review of Ravena Project

## 1. Compliance with Initial Vision

| Requirement | Status |
|---|---|
| EPUB reader for iOS | ✅ |
| Tap word → EN→RU translation | ✅ (via `UITextInputTokenizer`) |
| Translate full sentence | ✅ (long-press, changed from drag-select per request) |
| Personal dictionary with context | ✅ (SwiftData, deduplication by word+context) |
| Cloud-only translation (internet req.) | ✅ (DeepL + Claude via custom backend) |
| No iCloud sync for MVP | ✅ (intentionally omitted) |
| EPUB format only | ✅ |

The core vision has been completely fulfilled. Beyond the initial scope, the following were added: page-turning animations (`.pageCurl`), table of contents / chapter navigation, reading progress, and appearance settings (font/background/theme/margins/spacing).

---

## 2. Vulnerabilities — Fixed in this Session

| # | Issue | Location | Severity |
|---|---|---|---|
| 1 | `Authorization` token compared with `===` — potential timing attack. | `backend/src/index.ts` | Medium |
| 2 | Zip bomb: `EPUBParser` read files into memory without size limits. | `EPUBParser.swift` | Medium |
| 3 | No input length limits on the backend — allowed huge strings that could spike DeepL/Claude billing. | `backend/src/index.ts` | Low-Medium |
| 4 | Raw upstream errors (DeepL/Anthropic) leaked to the client in 502 responses. | `backend/src/index.ts` | Low |
| 5 | LLM sometimes wraps JSON in ```` ```json ```` despite prompts, which broke response parsing. | `backend/src/claudeWordLookup.ts` | Low (reliability) |

## 3. Vulnerabilities — Intentionally NOT Fixed (Backlog)

**Most Important:** The backend's entire authorization model uses **one shared secret hardcoded in the app**. Even with timing-safe comparison, the secret can be extracted via reverse-engineering (e.g., `strings`, Hopper). This allows anyone to bypass the app and drain your DeepL/Anthropic budget. For a public release, per-device/per-account tokens (e.g., Sign in with Apple + short-lived JWT) are strictly required.

Also not done:
- Server-side rate limiting beyond the Workers account limit (100k/day).
- CORS headers (not needed yet as the client is an iOS app, not a browser).

## 4. Subtle Bugs — Fixed in this Session

| # | Issue | Location |
|---|---|---|
| 1 | **Race on push+pop.** `popViewController` could be called before an ongoing `push` animation finished if EPUB parsing failed instantly. Fixed by pushing the fallback screen without animation. | `RootTabBarController.swift` |
| 2 | **Cache stampede.** Fast repeated taps on the same word triggered parallel network requests. Rewrote the cache using an `actor` to await inflight requests and reuse results. | `CachingTranslationService.swift` |
| 3 | **Reliance on implicit SwiftData autosave.** Added explicit `try? modelContext.save()` after saving words or exiting the reader screen to prevent data loss on crashes. | `DictionaryStore.swift`, `ReadingProgressStore.swift` |
| 4 | **Double popup on fast tap.** Tapping a second word while the first popup was still open resulted in nothing happening. Previous popups are now dismissed before a new one is presented. | `ReaderCoordinator.swift` |

## 5. Subtle Bugs — Audited and Confirmed Correct

- **`Task {}` inside `RootTabBarController.openReader` after `await`**: Re-verified that `UIViewController` subclasses are implicitly `@MainActor`. A normal `Task {}` created inside them inherits this isolation, so execution correctly stays on the main thread. Not a bug.
- **Security-scoped resource in `BookImporter`**: The `defer` block safely encompasses the entire function, including `await` suspension points. Not a bug.
- **SwiftData + `@MainActor`**: `DictionaryStore`, `ReadingProgressStore`, and `BookImporter` are all explicitly `@MainActor`. Heavy EPUB parsing is offloaded to `Task.detached`, ensuring `ModelContext` is only accessed on the main actor. Correctly implemented.

## 6. Known Limitations — Current Status

All items initially marked as low-priority backlog have now been addressed:

- **Pagination losing chapter tails** — Fixed by restricting setting ranges and implementing an emergency fallback size extension in `ChapterPaginator`.
- **Sentence extraction at page boundaries** — Fixed. The full chapter text is passed down, allowing cross-page sentences to be fully resolved.
- **Cache had no eviction** — Fixed by adopting an `LRUCache` (500 words / 200 sentences limits).
- **`activeReaderCoordinator` lifecycle** — Fixed by holding the coordinator in `ReaderViewController.retainedCoordinator` via ARC.
- **Orphaned files on deletion error** — Fixed by `LibraryFileReconciler` checking disk vs DB on every launch.
- **No deduplication on re-import** — Fixed using SHA-256 hashing.
- **XML OPF parser** — Fixed via namespace-aware parsing.

---

## 7. Review of New Features (TOC, Images, Footnotes, Covers, UI)

### Fixed in this Session

| # | Issue | Location |
|---|---|---|
| 1 | **Footnote cache scoping.** Cross-file footnotes were parsed repeatedly for every chapter. The cache was lifted to the book level (`parse()`) and passed down via `inout`. | `EPUBParser.swift` |

### Audited and Confirmed

- **Pagination with images & footnotes** — `NSTextAttachment` and superscript symbols seamlessly integrate with the existing `ChapterPaginator`.
- **Sentence offsets with images/footnotes** — The text used for sentence extraction is built after replacing footnote symbols, preventing invisible artifacts.
- **`NavigationLink` in `DictionaryListView`** — Works perfectly with the existing `UINavigationController` stack.
- **No Force Unwraps** — New TOC/footnote/image parsing uses safe optional unwrapping entirely to prevent crashes on malformed EPUBs.
- **`.externalStorage` for covers** — Confirmed that pulling `coverImageData` out of the primary SQLite row does not require a full migration plan for existing local databases.

### Low Priority Limitations Left As-Is

- **Footnote marker collision.** Extremely rare chance of a Private Use Area (`\u{E000}`) marker clashing if naturally present in the text. Ignored.
- **Footnotes without `epub:type` (EPUB2)** — Not supported due to a high risk of false positives.
- **Image decoding in SwiftUI `body`** — `UIImage(data:)` is called on every redraw in `LibraryListView`. Fine for personal libraries, but could be cached if it gets too large.
- **Inline SVG `<image>`** — Ignored. Only standard `<img>` tags are supported.

Everything found during this review has been addressed, except the **backend authorization model** (hardcoded secret), which remains the sole item in the technical debt backlog.
