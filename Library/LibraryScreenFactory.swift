import UIKit
import SwiftUI
import SwiftData

enum LibraryScreenFactory {
    static func makeViewController(
        modelContainer: ModelContainer,
        onOpenBook: @escaping (LibraryBook) -> Void
    ) -> UIViewController {
        let view = LibraryListView(onOpenBook: onOpenBook)
            .modelContainer(modelContainer)
        return UIHostingController(rootView: view)
    }
}

/*
Wiring it into the app (e.g. in the scene's root navigation controller):

    let library = LibraryScreenFactory.makeViewController(modelContainer: modelContainer) { book in
        guard let epubBook = try? EPUBParser().parse(fileURL: book.fileURL) else { return }

        let readerVC = ReaderViewController()

        let coordinator = ReaderCoordinator(
            readerViewController: readerVC,
            translationService: sharedTranslationService,
            dictionaryStore: DictionaryStore(modelContext: modelContainer.mainContext),
            progressStore: ReadingProgressStore(modelContext: modelContainer.mainContext),
            libraryBook: book,
            book: epubBook,
            presentingViewController: readerVC
        )
        // The coordinator configures the reader itself on init — no need to
        // call anything else on readerVC here.
        // Retain the coordinator via readerVC itself rather than a separate
        // property elsewhere — see ReaderViewController.retainedCoordinator.
        readerVC.retainedCoordinator = coordinator

        navigationController.pushViewController(readerVC, animated: true)
    }
*/
