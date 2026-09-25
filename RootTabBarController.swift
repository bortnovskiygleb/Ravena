import UIKit
import SwiftData
import Combine

final class RootTabBarController: UITabBarController {

    private let dependencies: AppDependencies
    private var cancellables = Set<AnyCancellable>()

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
        setupTabs()
        observeAppTheme()
        // Cheap (a directory listing of a handful of files, at most), so no
        // need to defer or background it — see LibraryFileReconciler's doc
        // comment for what this is cleaning up after.
        LibraryFileReconciler.removeOrphanedFiles(modelContext: dependencies.modelContainer.mainContext)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTabs() {
        let libraryNav = UINavigationController()
        let libraryVC = LibraryScreenFactory.makeViewController(
            modelContainer: dependencies.modelContainer
        ) { [weak self, weak libraryNav] book in
            guard let self, let libraryNav else { return }
            self.openReader(for: book, from: libraryNav)
        }
        libraryNav.viewControllers = [libraryVC]
        libraryNav.tabBarItem = UITabBarItem(
            title: "Библиотека",
            image: UIImage(systemName: "books.vertical"),
            tag: 0
        )

        let dictionaryVC = DictionaryScreenFactory.makeViewController(
            modelContainer: dependencies.modelContainer
        )
        let dictionaryNav = UINavigationController(rootViewController: dictionaryVC)
        dictionaryNav.tabBarItem = UITabBarItem(
            title: "Словарь",
            image: UIImage(systemName: "character.book.closed"),
            tag: 1
        )

        let settingsVC = SettingsScreenFactory.makeViewController()
        let settingsNav = UINavigationController(rootViewController: settingsVC)
        settingsNav.tabBarItem = UITabBarItem(
            title: "Настройки",
            image: UIImage(systemName: "gearshape"),
            tag: 2
        )

        viewControllers = [libraryNav, dictionaryNav, settingsNav]
    }

    private func openReader(for book: LibraryBook, from navigationController: UINavigationController) {
        let loadingViewController = makeLoadingViewController()
        // Not animated: this is just a spinner placeholder, and if parsing
        // fails almost instantly (e.g. the file is simply missing), an
        // animated push immediately followed by popViewController(animated:)
        // can race the push's own transition — UIKit doesn't guarantee that's
        // safe. An unanimated push has no transition to race.
        navigationController.pushViewController(loadingViewController, animated: false)

        Task {
            // Unzipping + parsing a whole EPUB can take a moment on a large book —
            // keep it off the main thread rather than freezing the tap.
            let epubBook = try? await Task.detached(priority: .userInitiated) {
                try EPUBParser().parse(fileURL: book.fileURL)
            }.value

            guard let epubBook else {
                navigationController.popViewController(animated: false)
                let alert = UIAlertController(
                    title: "Не удалось открыть книгу",
                    message: "Файл повреждён или отсутствует.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                navigationController.present(alert, animated: true)
                return
            }

            let readerVC = ReaderViewController()
            let coordinator = ReaderCoordinator(
                readerViewController: readerVC,
                translationService: dependencies.translationService,
                dictionaryStore: dependencies.dictionaryStore,
                progressStore: dependencies.progressStore,
                libraryBook: book,
                book: epubBook,
                presentingViewController: readerVC
            )
            // Tied to readerVC's own lifetime (see retainedCoordinator's doc
            // comment) rather than a property on this tab bar controller —
            // the coordinator is released automatically as soon as readerVC
            // is popped, instead of lingering until the next book is opened.
            readerVC.retainedCoordinator = coordinator

            // Swap the loading placeholder for the reader without an extra
            // push/pop animation — the user only sees "tap → brief spinner → book".
            var stack = navigationController.viewControllers
            stack[stack.count - 1] = readerVC
            navigationController.setViewControllers(stack, animated: false)
        }
    }

    private func makeLoadingViewController() -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .systemBackground

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        viewController.view.addSubview(spinner)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor),
        ])

        return viewController
    }

    private func observeAppTheme() {
        ReaderSettingsStore.shared.$settings
            .map(\.appTheme)
            .removeDuplicates()
            .sink { [weak self] theme in
                self?.overrideUserInterfaceStyle = theme.userInterfaceStyle
            }
            .store(in: &cancellables)
    }
}
