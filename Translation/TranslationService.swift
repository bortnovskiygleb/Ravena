import Foundation

// MARK: - Models

struct WordTranslation {
    let word: String
    let translation: String
    /// e.g. "noun", "verb" — helps disambiguate homonyms when saving to the dictionary.
    let partOfSpeech: String?
}

struct SentenceTranslation {
    let original: String
    let translated: String
}

enum TranslationError: Error {
    case network(Error)
    case invalidResponse
    case serverError(String)
}

// MARK: - Service protocol

/// Abstracts over the translation backend. The UI layer only ever talks to this
/// protocol — it never calls DeepL/Claude/Google directly from the device.
///
/// Why: API keys for those providers must never be embedded in the iOS app
/// bundle (they're trivially extractable via reverse engineering). The real
/// implementation (`APITranslationService`) calls *your own* backend, which
/// holds the provider keys and proxies the requests.
protocol TranslationService {
    /// Translates a single word, using the surrounding sentence to disambiguate meaning.
    func translateWord(_ word: String, contextSentence: String) async throws -> WordTranslation

    /// Translates a full sentence.
    func translateSentence(_ sentence: String) async throws -> SentenceTranslation
}
