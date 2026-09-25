import Foundation
import SwiftData
import CryptoKit

enum BookImportError: Error {
    case accessDenied
    case copyFailed(Error)
    case parseFailed(Error)
    /// The file's content exactly matches a book already in the library —
    /// `existingTitle` is included so the caller can show a specific message.
    case duplicate(existingTitle: String)
}

@MainActor
final class BookImporter {

    private let modelContext: ModelContext
    private let parser = EPUBParser()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// `sourceURL` is typically a security-scoped URL handed to us by
    /// UIDocumentPickerViewController — it points at wherever the user picked
    /// the file from (iCloud Drive, Files app, etc.), not at our sandbox.
    /// We copy it into our own storage so the app still has access after the
    /// picker session ends and the original location's permission expires.
    func importBook(from sourceURL: URL) async throws {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw BookImportError.accessDenied
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        let sourceData: Data
        do {
            sourceData = try Data(contentsOf: sourceURL)
        } catch {
            throw BookImportError.copyFailed(error)
        }

        // Hash the bytes *before* copying or parsing anything — if this exact
        // file was already imported (regardless of what it's named or where
        // it came from this time), there's no point writing a second copy or
        // spending time parsing it again.
        let contentHash = await Task.detached(priority: .userInitiated) {
            Self.sha256Hex(of: sourceData)
        }.value

        if let existing = try? findExistingBook(withContentHash: contentHash) {
            throw BookImportError.duplicate(existingTitle: existing.title)
        }

        let destinationURL = try makeDestinationURL()
        do {
            try sourceData.write(to: destinationURL)
        } catch {
            throw BookImportError.copyFailed(error)
        }

        // Parsing walks the whole EPUB (unzip + XML), so keep it off the main actor.
        let parsedBook: EPUBBook
        do {
            parsedBook = try await Task.detached(priority: .userInitiated) { [parser] in
                try parser.parse(fileURL: destinationURL)
            }.value
        } catch {
            // Don't leave an unreadable file cluttering the library folder.
            try? FileManager.default.removeItem(at: destinationURL)
            throw BookImportError.parseFailed(error)
        }

        let entry = LibraryBook(
            title: parsedBook.title,
            author: parsedBook.author,
            fileName: destinationURL.lastPathComponent,
            contentHash: contentHash,
            coverImageData: parsedBook.coverImageData,
            totalChapters: max(parsedBook.chapters.count, 1)
        )
        modelContext.insert(entry)
        try? modelContext.save()
    }

    // MARK: - Helpers

    private func findExistingBook(withContentHash hash: String) throws -> LibraryBook? {
        var descriptor = FetchDescriptor<LibraryBook>(predicate: #Predicate { $0.contentHash == hash })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func makeDestinationURL() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let booksDirectory = documents.appendingPathComponent("Books", isDirectory: true)

        if !FileManager.default.fileExists(atPath: booksDirectory.path) {
            try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        }

        return booksDirectory.appendingPathComponent("\(UUID().uuidString).epub")
    }

    private nonisolated static func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
