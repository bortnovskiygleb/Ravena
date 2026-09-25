import UIKit
import SwiftUI
import SwiftData

enum DictionaryScreenFactory {
    /// Wraps the SwiftUI list in a UIHostingController so it can be pushed onto
    /// a UIKit UINavigationController like any other screen.
    static func makeViewController(modelContainer: ModelContainer) -> UIViewController {
        let view = DictionaryListView()
            .modelContainer(modelContainer)
        return UIHostingController(rootView: view)
    }
}

/*
Where the ModelContainer is created — typically once, in your app/scene entry point:

    let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: SavedWord.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

Then both the dictionary screen and the reader's save-to-dictionary flow share
the same container's mainContext:

    let dictionaryStore = DictionaryStore(modelContext: modelContainer.mainContext)
    let dictionaryScreen = DictionaryScreenFactory.makeViewController(modelContainer: modelContainer)
*/
