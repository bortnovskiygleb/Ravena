# Architecture of Ravena

MVP: book import → reading → word/sentence translation → save to dictionary → reading progress → appearance settings. Below are all implemented layers and where to look if modifications are needed.

## 1. EPUB Parsing
| File | Role |
|---|---|
| `EPUBModels.swift` | `EPUBBook / EPUBChapter / EPUBParagraph` models |
| `EPUBParser.swift` | ZIP extraction → `container.xml` → `.opf` (manifest+spine) → chapter text via SwiftSoup |
| `WordTokenizer.swift` | Paragraph word tokenization via `NLTokenizer` (for reference; actual tap logic differs — see below) |

## 2. Reading Screen
| File | Role |
|---|---|
| `ReaderViewController.swift` | `UITextView` + tap → word, long-press (0.4s) → sentence via `UITextInputTokenizer`; renders based on `ReaderSettings`; tracks scrolling |
| `SentenceExtractor.swift` | Finds the sentence around a word via `NLTokenizer(.sentence)` |
| `ReadingProgressBar.swift` | Thin progress bar at the top of the screen |

## 3. Translation
| File | Role |
|---|---|
| `TranslationService.swift` | Protocol + `WordTranslation`/`SentenceTranslation` models |
| `APITranslationService.swift` | HTTP client pointing to **our own** backend (not directly to DeepL/LLM) |
| `CachingTranslationService.swift` | In-memory cache by `word+context` per session |
| `TranslationPopupViewController.swift` | Bottom sheet: loading / word result / sentence result / error |
| `ReaderCoordinator.swift` | Glues reader ↔ translation ↔ popup ↔ dictionary ↔ progress |

### Backend (`backend/`)
| File | Role |
|---|---|
| `wrangler.toml` | Cloudflare Workers config (free tier, 100k reqs/day) |
| `src/index.ts` | Router: `/translate/sentence` → DeepL, `/translate/word` → Claude |
| `src/deepl.ts` | DeepL client — sentence translation |
| `src/claudeWordLookup.ts` | Claude Haiku client — word translation with context + part of speech |
| `README.md` | Deployment, keys, known limitations (shared secret instead of per-user auth) |

## 4. Personal Dictionary
| File | Role |
|---|---|
| `SavedWord.swift` | SwiftData model: word, translation, part of speech, context, book, date |
| `DictionaryStore.swift` | Saving with deduplication by word+context |
| `DictionaryListView.swift` | SwiftUI list (`@Query`, auto-updating), swipe-to-delete |
| `DictionaryScreenFactory.swift` | `UIHostingController` wrapper for UIKit navigation |

## 5. Library and Import
| File | Role |
|---|---|
| `LibraryBook.swift` | SwiftData book model + progress fields |
| `BookImporter.swift` | Copies EPUB into app sandbox, parses metadata, cleans up on error |
| `EPUBFilePicker.swift` | `UIDocumentPickerViewController` wrapper, filters for `.epub` |
| `LibraryListView.swift` | Book list, import via "+", file+record deletion, read percentage |
| `LibraryScreenFactory.swift` | `UIHostingController` wrapper + reader docking example |

## 6. Reading Progress
| File | Role |
|---|---|
| `ReadingProgressStore.swift` | Position write debouncer (800ms) + `flush()` on screen dismissal |
| *(Fields in `LibraryBook`)* | `totalChapters`, `lastReadChapterIndex`, `lastReadScrollFraction`, `progressFraction` |

## 7. Settings
| File | Role |
|---|---|
| `ReaderSettings.swift` | Font size/style, reading background, app theme |
| `ReaderSettingsStore.swift` | Singleton, `@Published` + `UserDefaults` persistence |
| `SettingsView.swift` | Form with text preview and background swatches |
| `SettingsScreenFactory.swift` | `UIHostingController` wrapper |

---

## Key Architectural Decisions

- **Word tap/long-press** — Uses built-in `UITextInputTokenizer` (`closestPosition` + `rangeEnclosingPosition`), rather than manually traversing `NSTextLayoutManager`: more reliable and independent of TextKit 1 vs 2.
- **No API keys in the app** — A custom Cloudflare Workers backend proxy holds DeepL/Anthropic secrets; the iOS client only routes there.
- **Hybrid translation** — DeepL for sentences (cheaper, higher quality for connected text), LLM for words (accounts for context, determines part of speech).
- **SwiftUI + UIKit mix** — Screens with lists (`@Query` via SwiftData) are built in SwiftUI and wrapped in `UIHostingController`; the reader itself is UIKit (needs fine control over gestures and TextKit).
- **All appearance settings preserve relative scroll position** — Whether changing font size or restoring read position between sessions.

## What's Left (Intentionally Postponed)

- **App Entry Point** — Tab bar/navigation connecting Library, Dictionary, and Settings, and `ModelContainer` creation on startup.
- **Chapter Navigation** — `ReaderViewController` currently shows a chapter at a time; previous/next chapter logic is unimplemented.
- **Production Backend Auth** — Shared secret is fine for personal use/beta; per-user tokens are needed for public release.
- **Handling non-standard EPUBs** — DRM-protected files, broken archives, complex layout (tables, images) — currently skipped or crash.
- **iCloud Dictionary Sync** — Intentionally omitted for MVP.
