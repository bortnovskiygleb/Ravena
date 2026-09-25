# Ravena (EPUB Reader with Translation)

**Ravena** is an iOS application for reading EPUB books with built-in contextual translation (English → Russian) and a spaced repetition system for learning new words.

## Project Documentation

Detailed descriptions of various aspects of the project are available in separate files:

- [**FEATURES.md**](FEATURES.md) — Full feature list (import, reading, dictionary, settings).
- [**ARCHITECTURE.md**](ARCHITECTURE.md) — Architecture overview, tech stack, and layers (SwiftUI + UIKit).
- [**SETUP.md**](SETUP.md) — Instructions for building the project locally in Xcode and running it on a real device.
- [**REVIEW.md**](REVIEW.md) — Code review, list of known limitations, vulnerabilities, and fixed bugs.
- [**backend/README.md**](backend/README.md) — Backend documentation (Cloudflare Workers proxy for DeepL and Anthropic).

## Key Features

- **EPUB Reading**: Page-by-page turning, table of contents, footnotes, and inline image support.
- **Smart Translation**: Tap a word for contextual translation, long-press to translate an entire sentence.
- **Personal Dictionary**: Save translated words with their context and learn them using Spaced Repetition.
- **Local Library**: Books are copied into the app's local storage; original files are no longer needed.
- **Flexible Settings**: Adjust font size, margins, line spacing, and theme (light, sepia, night, dark) on the fly.

## Requirements

- **iOS 17.0+**
- Deployed proxy backend for translation APIs (see `backend/README.md`). Internet connection is only required for the translation process itself (all other features work completely offline).
