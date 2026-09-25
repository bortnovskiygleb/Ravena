# App Description — Ravena

**Ravena** is an EPUB book reader with on-the-fly word and sentence translation (English → Russian) and a built-in spaced repetition mechanism for learning words. Translation is cloud-based and requires an internet connection.

The app consists of three tabs (tab bar): **Library**, **Dictionary**, **Settings**. The reading screen opens on top of the Library and is not a separate tab.

---

## Tab 1. Library

The app's starting screen is a list of all imported books.

**Book List**
- Cover (44×60 thumbnail), title, author
- Reading progress bar + percentage (overall book progress, not just the current chapter)
- Empty state with a hint if no books have been added yet

**Importing a Book**
- "+" button in the navigation bar → system file browser (only `.epub`)
- The file is copied to the app's internal storage — access to the original file (e.g., iCloud Drive) is no longer required
- Cover, author, language, and chapter count are determined automatically upon import
- **Duplicate Protection**: File content is hashed (SHA-256) before copying — if the same book already exists in the library, it won't be imported again, and a message showing the existing book's name is displayed
- If the file is corrupted or not a valid EPUB — a user-friendly error message is shown instead of crashing

**Deletion**
- Swipe on a book — deletes both the database record and the file
- A background check runs on every app launch: files without a corresponding database record (e.g., due to a deletion failure) are automatically cleaned up

**Opening a Book** — tapping a book opens it at the exact page where reading was last interrupted (or from the beginning if opened for the first time).

---

## Reading Screen

Opens on top of the Library when a book is selected. The primary mode is page-by-page turning (no continuous scroll) with a `.pageCurl` animation.

**Word Translation**
- Tap any word — a bottom sheet slides up with the translation (via a cloud service, considering the sentence context — e.g., distinguishing "bank" as a river bank vs. a financial institution)
- Shows translation and part of speech
- "Add to Dictionary" button — saves the word along with its context sentence and the book title

**Sentence Translation**
- Long press on a word — translates the entire sentence it belongs to (not just the single word)

**Footnotes**
- Edition footnotes (including those placed in a separate file for the whole book) are displayed as a small superscript number right in the text
- Tap the number — pops up a panel with the footnote text

**Images**
- Illustrations from the book are embedded directly in the text flow, automatically scaled to page width

**Mathematical Formulas**
- Partial support: if the publisher included a text equivalent in the markup (common for accessibility), it is shown in square brackets; full formula rendering is not supported

**Table of Contents**
- The list button in the navigation bar opens the TOC, built from the actual TOC document (not just guessed from headers)
- A single physical chapter file may contain multiple TOC entries — navigation jumps to the specific section inside the file, not just the beginning
- Sections without a title in the original TOC (covers, publisher utility pages) are hidden from the list, but are still accessible via normal page turning

**Chapter Navigation** — arrows in the navigation bar switch to the previous/next chapter entirely.

**Progress** — a thin bar at the top + a "N pages left" label showing remaining pages in the current chapter (not the whole book).

**On-the-fly Appearance** — changes in Settings (font, background, margins, spacing) are applied immediately without leaving the reading screen; the reader attempts to keep the exact reading position during pagination recalculation.

---

## Tab 2. Dictionary

A list of all saved words.

**List**
- Each row displays only the word and a small translation
- Tap to open full details: word, translation, part of speech, context sentence, book title, date added, and review status
- Swipe to delete

**Word Review (Spaced Repetition)**
- If words are ready for review, a "Review Words" button with a counter appears at the top
- Review mode works flashcard-style: word → "Show Translation" button → translation, part of speech, and context → grade **Forgot** / **Remember** / **Easy**
- The grade determines when the word will appear again: "Forgot" — tomorrow, "Remember"/"Easy" — intervals gradually increase (similar to Anki)
- At the end of the session, a screen shows the number of reviewed words

---

## Tab 3. Settings

All settings apply immediately and globally across all books.

| Setting | Range |
|---|---|
| Font Size | 14–32pt |
| Font Style | System / Serif / Monospaced |
| Reading Background | White / Sepia / Night / Black |
| App Theme | System / Light / Dark |
| Margins | 8–40pt |
| Line Spacing | 0–10pt |

At the bottom of the screen is a live preview: a text snippet styled exactly how the book page will look with current settings.

---

## Internet Requirements

Word and sentence translations always require internet (cloud service). Everything else — importing, reading, TOC, footnotes, images, dictionary, reviews — works completely offline.

---

## What's Intentionally Missing (For Now)

- Book text search
- Bookmarks (apart from the automatic "continue reading" progress)
- Arbitrary text highlighting (only single word saving is supported)
- Language pairs other than English → Russian
- Cross-device synchronization (iCloud, etc.)
- Full mathematical formula rendering

Technical details on how this is built internally can be found in `ARCHITECTURE.md`.
