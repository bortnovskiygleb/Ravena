import Foundation
import SwiftData

final class AppDependencies {

    let modelContainer: ModelContainer
    let translationService: TranslationService

    init() {
        do {
            modelContainer = try ModelContainer(for: LibraryBook.self, SavedWord.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // TODO: replace with your deployed Worker URL from backend/README.md
        // (e.g. "https://reader-translate-proxy.your-subdomain.workers.dev").
        let backendURL = URL(string: "https://reader-translate-proxy.example.workers.dev")!
        translationService = CachingTranslationService(
            wrapping: APITranslationService(baseURL: backendURL)
        )
    }

    // Fetched fresh each time rather than cached as a stored property — SwiftData
    // stores are cheap to create and this avoids any risk of a stale ModelContext
    // if the container's main context identity ever changes.
    var dictionaryStore: DictionaryStore {
        DictionaryStore(modelContext: modelContainer.mainContext)
    }

    var progressStore: ReadingProgressStore {
        ReadingProgressStore(modelContext: modelContainer.mainContext)
    }
}
