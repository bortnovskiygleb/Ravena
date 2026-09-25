import Foundation
import SwiftData

/// A book's file and its LibraryBook database record are meant to always
/// exist together, but a few things can knock them out of sync: a failed
/// file deletion (permissions, file briefly in use) when a book is removed,
/// or the app being killed between copying an imported file in and saving
/// its record. Rather than trying to guarantee perfect atomicity at every
/// call site — some of those failure modes are outside our control in the
/// moment — this reconciles the two on every launch: the database is the
/// source of truth, and any file not referenced by a LibraryBook gets removed.
@MainActor
enum LibraryFileReconciler {

    static func removeOrphanedFiles(modelContext: ModelContext) {
        guard let booksDirectory = booksDirectoryURL(),
              let filesOnDisk = try? FileManager.default.contentsOfDirectory(
                  at: booksDirectory, includingPropertiesForKeys: nil
              )
        else { return }

        let knownFileNames: Set<String>
        do {
            let books = try modelContext.fetch(FetchDescriptor<LibraryBook>())
            knownFileNames = Set(books.map(\.fileName))
        } catch {
            // If we can't confirm what's actually referenced, don't risk
            // deleting anything — better a harmless leftover file than
            // accidentally removing a book that's still in use.
            return
        }

        for fileURL in filesOnDisk where !knownFileNames.contains(fileURL.lastPathComponent) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func booksDirectoryURL() -> URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Books", isDirectory: true)
    }
}
