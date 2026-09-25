import Foundation
import SwiftData

@MainActor
final class ReadingProgressStore {

    private let modelContext: ModelContext
    private var debounceTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Call on every scroll update — this is cheap to call often. The actual
    /// SwiftData write is debounced by 800ms so a continuous scroll gesture
    /// doesn't hammer disk on every frame.
    func recordProgress(for book: LibraryBook, chapterIndex: Int, scrollFraction: Double) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            book.lastReadChapterIndex = chapterIndex
            book.lastReadScrollFraction = scrollFraction
        }
    }

    /// Call immediately (no debounce) when leaving the reader screen or the
    /// app is about to background — we don't want to lose the last 800ms of
    /// progress to a cancelled debounce.
    func flush(for book: LibraryBook, chapterIndex: Int, scrollFraction: Double) {
        debounceTask?.cancel()
        book.lastReadChapterIndex = chapterIndex
        book.lastReadScrollFraction = scrollFraction
        // Explicit save here (unlike the debounced recordProgress path) — this
        // fires when the user is actually leaving the reader, i.e. exactly the
        // moment we most need the write to survive even if the app is killed
        // a moment later, rather than waiting on SwiftData's implicit autosave.
        try? modelContext.save()
    }
}
