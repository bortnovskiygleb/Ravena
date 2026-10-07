import Foundation
import SwiftData

@MainActor
final class DictionaryStore {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Saves a new entry, or updates the translation if this exact word+sentence
    /// pair was already saved (e.g. the user tapped the same word twice).
    func save(
        word: String,
        translation: String,
        partOfSpeech: String?,
        transcription: String?,
        contextSentence: String,
        bookTitle: String?
    ) {
        let descriptor = FetchDescriptor<SavedWord>(
            predicate: #Predicate { $0.word == word && $0.contextSentence == contextSentence }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.translation = translation
            existing.partOfSpeech = partOfSpeech
            // Only overwrite a user-edited transcription if the API returned a
            // non-nil value — preserves manual edits when the user re-saves the same word.
            if let transcription {
                existing.transcription = transcription
            }
            try? modelContext.save()
            return
        }

        let entry = SavedWord(
            word: word,
            translation: translation,
            partOfSpeech: partOfSpeech,
            transcription: transcription,
            contextSentence: contextSentence,
            bookTitle: bookTitle
        )
        modelContext.insert(entry)
        // Explicit save rather than relying solely on SwiftData's implicit
        // autosave — a word tapped and saved just before the user force-quits
        // or the app crashes shouldn't be lost to an autosave cycle that
        // hadn't run yet.
        try? modelContext.save()
    }

    func delete(_ entry: SavedWord) {
        modelContext.delete(entry)
    }
}
