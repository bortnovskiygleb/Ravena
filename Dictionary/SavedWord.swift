import Foundation
import SwiftData

@Model
final class SavedWord {
    var word: String
    var translation: String
    var partOfSpeech: String?
    var contextSentence: String
    var bookTitle: String?
    var dateAdded: Date

    // MARK: - Spaced repetition state (simplified SM-2, see SpacedRepetitionScheduler)

    /// When this word is next due for review. Defaults to "now" so a
    /// newly-saved word shows up in the very next review session rather
    /// than waiting around unreviewed.
    var nextReviewDate: Date = Date.now
    /// Current interval between reviews, in days. Grows when a word is
    /// remembered, resets to 1 when it's forgotten.
    var intervalDays: Double = 0
    /// SM-2's "ease factor" — how quickly the interval grows for this word.
    /// 2.5 is SM-2's standard starting value; never allowed below 1.3
    /// (SM-2's own floor) so a hard word doesn't spiral to near-zero growth.
    var easeFactor: Double = 2.5
    /// Consecutive successful reviews since the last time this word was
    /// forgotten — reset to 0 on "Забыл".
    var repetitionCount: Int = 0

    init(
        word: String,
        translation: String,
        partOfSpeech: String?,
        contextSentence: String,
        bookTitle: String?,
        dateAdded: Date = .now
    ) {
        self.word = word
        self.translation = translation
        self.partOfSpeech = partOfSpeech
        self.contextSentence = contextSentence
        self.bookTitle = bookTitle
        self.dateAdded = dateAdded
    }
}
