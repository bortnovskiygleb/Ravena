import Foundation

/// Wraps any TranslationService with a cache, keyed on word+context (the same
/// word can mean different things in different sentences, so context is part
/// of the cache key). This is a session-lifetime cache only — the user's
/// permanent saved-words dictionary is a separate, persisted store (SwiftData),
/// not this cache.
final class CachingTranslationService: TranslationService {

    private let store: TranslationCacheStore

    init(wrapping service: TranslationService) {
        self.store = TranslationCacheStore(wrapped: service)
    }

    func translateWord(_ word: String, contextSentence: String) async throws -> WordTranslation {
        try await store.translateWord(word, contextSentence: contextSentence)
    }

    func translateSentence(_ sentence: String) async throws -> SentenceTranslation {
        try await store.translateSentence(sentence)
    }
}

/// An actor (not a lock+dictionary) specifically so that a second call for a
/// key that's already being fetched can *await the same in-flight request*
/// instead of firing a duplicate one. With a plain lock, two near-simultaneous
/// calls for the same word (e.g. a fast double-tap) would both see a cache
/// miss and both hit the network — a "cache stampede" that wastes a paid
/// translation call. Tracking the in-flight Task per key closes that gap.
private actor TranslationCacheStore {
    private let wrapped: TranslationService
    // Bounded rather than plain dictionaries — an unbounded cache would grow
    // for the entire app session; realistically that's fine for "one book,
    // one sitting", but nothing stops a very long multi-day session from
    // accumulating thousands of entries otherwise. Sentences get a lower cap
    // since each entry is bigger (longer strings) and looked up less often
    // than individual words.
    private var wordCache = LRUCache<String, WordTranslation>(capacity: 500)
    private var sentenceCache = LRUCache<String, SentenceTranslation>(capacity: 200)
    private var inFlightWordRequests: [String: Task<WordTranslation, Error>] = [:]
    private var inFlightSentenceRequests: [String: Task<SentenceTranslation, Error>] = [:]

    init(wrapped: TranslationService) {
        self.wrapped = wrapped
    }

    func translateWord(_ word: String, contextSentence: String) async throws -> WordTranslation {
        let key = "\(word.lowercased())|\(contextSentence)"

        if let cached = wordCache.value(forKey: key) { return cached }
        if let inFlight = inFlightWordRequests[key] { return try await inFlight.value }

        let task = Task<WordTranslation, Error> { [wrapped] in
            try await wrapped.translateWord(word, contextSentence: contextSentence)
        }
        inFlightWordRequests[key] = task

        do {
            let result = try await task.value
            wordCache.setValue(result, forKey: key)
            inFlightWordRequests[key] = nil
            return result
        } catch {
            inFlightWordRequests[key] = nil
            throw error
        }
    }

    func translateSentence(_ sentence: String) async throws -> SentenceTranslation {
        if let cached = sentenceCache.value(forKey: sentence) { return cached }
        if let inFlight = inFlightSentenceRequests[sentence] { return try await inFlight.value }

        let task = Task<SentenceTranslation, Error> { [wrapped] in
            try await wrapped.translateSentence(sentence)
        }
        inFlightSentenceRequests[sentence] = task

        do {
            let result = try await task.value
            sentenceCache.setValue(result, forKey: sentence)
            inFlightSentenceRequests[sentence] = nil
            return result
        } catch {
            inFlightSentenceRequests[sentence] = nil
            throw error
        }
    }
}
