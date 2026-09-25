import Foundation

/// How well the person remembered a word when reviewing it.
enum ReviewRating {
    case again  // forgot it entirely
    case good   // remembered, with some effort
    case easy   // remembered instantly
}

/// The spaced-repetition fields on SavedWord, decoupled from the SwiftData
/// model itself — keeps the scheduling math a pure function you can test
/// without spinning up a ModelContext.
struct SpacedRepetitionState {
    var intervalDays: Double
    var easeFactor: Double
    var repetitionCount: Int
    var nextReviewDate: Date
}

/// A simplified version of the SM-2 algorithm (the same family Anki's
/// scheduler descends from). Deliberately simpler than full SM-2 — three
/// rating buttons instead of a 0-5 quality scale — since for vocabulary
/// review "forgot / remembered / remembered easily" is plenty of signal
/// without asking the person to self-rate on a scale they'd have to think
/// about every single card.
enum SpacedRepetitionScheduler {

    private static let minimumEaseFactor = 1.3 // SM-2's own floor — below this, intervals barely grow at all

    static func schedule(current: SpacedRepetitionState, rating: ReviewRating, now: Date = .now) -> SpacedRepetitionState {
        var state = current

        switch rating {
        case .again:
            state.repetitionCount = 0
            state.intervalDays = 1
            state.easeFactor = max(minimumEaseFactor, state.easeFactor - 0.2)

        case .good:
            state.repetitionCount += 1
            state.intervalDays = nextInterval(repetitionCount: state.repetitionCount, previousInterval: state.intervalDays, easeFactor: state.easeFactor)

        case .easy:
            state.repetitionCount += 1
            state.easeFactor += 0.15
            let baseInterval = nextInterval(repetitionCount: state.repetitionCount, previousInterval: state.intervalDays, easeFactor: state.easeFactor)
            // "Easy" grows the interval further still, on top of the normal
            // curve — rewards words that clearly don't need frequent review.
            state.intervalDays = baseInterval * 1.3
        }

        state.nextReviewDate = now.addingTimeInterval(state.intervalDays * 86400)
        return state
    }

    /// SM-2's standard interval progression: 1 day, then 6 days, then
    /// previous interval × ease factor for every review after that.
    private static func nextInterval(repetitionCount: Int, previousInterval: Double, easeFactor: Double) -> Double {
        switch repetitionCount {
        case 1: return 1
        case 2: return 6
        default: return max(previousInterval, 1) * easeFactor
        }
    }
}
