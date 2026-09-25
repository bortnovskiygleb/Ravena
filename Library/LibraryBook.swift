import Foundation
import SwiftData

@Model
final class LibraryBook {
    var title: String
    var author: String
    /// File name only (e.g. "3F2A1B-....epub") — the file lives in the app's
    /// own Documents/Books/ folder, not at whatever path the user picked it from.
    var fileName: String
    /// SHA-256 of the file's bytes, hex-encoded — lets BookImporter recognize
    /// "you already imported this exact file" regardless of what it was named
    /// or where it was picked from. Defaulted (rather than required) so
    /// existing SwiftData stores migrate without a full migration plan.
    var contentHash: String = ""
    var dateAdded: Date

    /// Cover image bytes extracted at import time (EPUBBook.coverImageData) —
    /// nil for books with no declared cover. .externalStorage keeps this out
    /// of the main SQLite row (SwiftData writes it as a separate file
    /// instead), which is the right call for image-sized blobs.
    @Attribute(.externalStorage) var coverImageData: Data?

    /// Reading position, updated as the user turns pages. Chapter index + how
    /// far through that chapter by page count (0...1) is enough to resume close
    /// to where they left off, and to compute an overall book percentage.
    /// Named "scrollFraction" from the original continuous-scroll reader; the
    /// meaning is now "page index / total pages in chapter" instead, but the
    /// 0...1 range and everything that reads it stayed the same, so the field
    /// wasn't renamed (a SwiftData schema/migration change wasn't worth it here).
    var totalChapters: Int
    var lastReadChapterIndex: Int
    var lastReadScrollFraction: Double

    init(
        title: String,
        author: String,
        fileName: String,
        contentHash: String,
        coverImageData: Data?,
        totalChapters: Int,
        dateAdded: Date = .now
    ) {
        self.title = title
        self.author = author
        self.fileName = fileName
        self.contentHash = contentHash
        self.coverImageData = coverImageData
        self.totalChapters = totalChapters
        self.dateAdded = dateAdded
        self.lastReadChapterIndex = 0
        self.lastReadScrollFraction = 0
    }

    var fileURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Overall progress through the book, 0...1, combining completed chapters
    /// with partial progress through the current one.
    var progressFraction: Double {
        guard totalChapters > 0 else { return 0 }
        let completed = Double(lastReadChapterIndex) + lastReadScrollFraction
        return min(max(completed / Double(totalChapters), 0), 1)
    }
}
