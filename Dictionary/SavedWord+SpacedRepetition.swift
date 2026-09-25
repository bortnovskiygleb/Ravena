import Foundation

extension SavedWord {
    /// Applies a review rating and updates this word's due date in place.
    /// Caller is responsible for saving the modelContext afterward.
    func applyReview(rating: ReviewRating, now: Date = .now) {
        let currentState = SpacedRepetitionState(
            intervalDays: intervalDays,
            easeFactor: easeFactor,
            repetitionCount: repetitionCount,
            nextReviewDate: nextReviewDate
        )
        let newState = SpacedRepetitionScheduler.schedule(current: currentState, rating: rating, now: now)
        intervalDays = newState.intervalDays
        easeFactor = newState.easeFactor
        repetitionCount = newState.repetitionCount
        nextReviewDate = newState.nextReviewDate
    }
}
