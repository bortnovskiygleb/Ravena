# Читалка EPUB с переводом — обзор архитектуры

MVP: импорт книги → чтение → перевод слова/предложения → сохранение в словарь →
прогресс → настройки внешнего вида. Ниже — все реализованные слои и куда
смотреть, если нужно что-то поправить.

## 1. Парсинг EPUB
| Файл | Роль |
|---|---|
| `EPUBModels.swift` | Модели `EPUBBook / EPUBChapter / EPUBParagraph` |
| `EPUBParser.swift` | Распаковка ZIP → `container.xml` → `.opf` (манифест+spine) → текст глав через SwiftSoup |
| `WordTokenizer.swift` | Разбивка параграфа на слова через `NLTokenizer` (для справки; сам тап реализован иначе — см. ниже) |

## 2. Экран чтения
| Файл | Роль |
|---|---|
| `ReaderViewController.swift` | `UITextView` + тап → слово, long-press (0.4с) → предложение, через `UITextInputTokenizer`; рендер с учётом `ReaderSettings`; отслеживание скролла |
| `SentenceExtractor.swift` | Находит предложение вокруг слова через `NLTokenizer(.sentence)` |
| `ReadingProgressBar.swift` | Тонкая полоса прогресса вверху экрана |

## 3. Перевод
| Файл | Роль |
|---|---|
| `TranslationService.swift` | Протокол + модели `WordTranslation`/`SentenceTranslation` |
| `APITranslationService.swift` | HTTP-клиент к **своему** бэкенду (не напрямую в DeepL/LLM) |
| `CachingTranslationService.swift` | In-memory кеш по `слово+контекст` на сессию |
| `TranslationPopupViewController.swift` | Bottom sheet: loading / результат слова / результат предложения / ошибка |
| `ReaderCoordinator.swift` | Склеивает reader ↔ перевод ↔ попап ↔ словарь ↔ прогресс |

### Бэкенд (`backend/`)
| Файл | Роль |
|---|---|
| `wrangler.toml` | Конфиг Cloudflare Workers (бесплатный тариф, 100k запросов/день) |
| `src/index.ts` | Роутер: `/translate/sentence` → DeepL, `/translate/word` → Claude |
| `src/deepl.ts` | Клиент DeepL — перевод предложений |
| `src/claudeWordLookup.ts` | Клиент Claude Haiku — перевод слова с учётом контекста + часть речи |
| `README.md` | Деплой, ключи, известные ограничения (общий секрет вместо per-user auth) |

## 4. Личный словарь
| Файл | Роль |
|---|---|
| `SavedWord.swift` | SwiftData-модель: слово, перевод, часть речи, контекст, книга, дата |
| `DictionaryStore.swift` | Сохранение с дедупликацией по слову+контексту |
| `DictionaryListView.swift` | SwiftUI-список (`@Query`, авто-обновление), swipe-to-delete |
| `DictionaryScreenFactory.swift` | `UIHostingController`-обёртка для UIKit-навигации |

## 5. Библиотека и импорт
| Файл | Роль |
|---|---|
| `LibraryBook.swift` | SwiftData-модель книги + поля прогресса |
| `BookImporter.swift` | Копирует EPUB в песочницу приложения, парсит метаданные, чистит за собой при ошибке |
| `EPUBFilePicker.swift` | Обёртка `UIDocumentPickerViewController`, фильтр `.epub` |
| `LibraryListView.swift` | Список книг, импорт по "+", удаление файла+записи, процент прочитанного |
| `LibraryScreenFactory.swift` | `UIHostingController`-обёртка + пример стыковки с ридером |

## 6. Прогресс чтения
| Файл | Роль |
|---|---|
| `ReadingProgressStore.swift` | Дебаунс-запись позиции (800мс) + `flush()` при закрытии экрана |
| *(поля в `LibraryBook`)* | `totalChapters`, `lastReadChapterIndex`, `lastReadScrollFraction`, `progressFraction` |

## 7. Настройки
| Файл | Роль |
|---|---|
| `ReaderSettings.swift` | Размер/стиль шрифта, фон для чтения, тема приложения |
| `ReaderSettingsStore.swift` | Синглтон, `@Published` + персистентность в `UserDefaults` |
| `SettingsView.swift` | Форма с превью текста и свотчами фона |
| `SettingsScreenFactory.swift` | `UIHostingController`-обёртка |

---

## Ключевые архитектурные решения по ходу разработки

- **Тап/long-press по слову** — через встроенный `UITextInputTokenizer`
  (`closestPosition` + `rangeEnclosingPosition`), а не через ручной обход
  `NSTextLayoutManager`: надёжнее и не зависит от TextKit 1 vs 2.
- **API-ключи никогда не в приложении** — свой бэкенд-прокси на Cloudflare
  Workers держит секреты DeepL/Anthropic, iOS-клиент ходит только туда.
- **Гибридный перевод** — DeepL для предложений (дешевле, качественнее для
  связного текста), LLM для слов (учитывает контекст, определяет часть речи).
- **SwiftUI + UIKit вперемешку** — экраны со списками (`@Query` на SwiftData)
  сделаны на SwiftUI и обёрнуты `UIHostingController`; сам ридер — UIKit
  (нужен точный контроль над жестами и TextKit).
- **Все настройки перерисовки сохраняют относительную позицию скролла** —
  и при смене шрифта, и при восстановлении места чтения между сессиями.

## Что ещё не сделано (осознанно отложено)

- **Точка входа приложения** — таб-бар/навигация, связывающая Библиотеку,
  Словарь и Настройки в одно целое, создание `ModelContainer` при старте.
- **Навигация между главами** — сейчас `ReaderViewController` показывает
  одну главу целиком; переключение вперёд/назад не реализовано.
- **Продакшн-авторизация бэкенда** — общий секрет годится для личного
  использования/беты, для публичного релиза нужны per-user токены.
- **Обработка нестандартных EPUB** — DRM-защищённые файлы, битые архивы,
  сложная вёрстка (таблицы, сноски, картинки) — пока выкидываются или падают.
- **iCloud-синхронизация словаря** — сознательно отложена на старте.
