import UIKit

/// Owns the translation popup lifecycle and persistence side effects; routes
/// events between ReaderViewController (taps/long-presses/progress) and the
/// network/storage services. Chapter and page navigation are no longer this
/// coordinator's concern — ReaderViewController owns the book and drives its
/// own UIPageViewController internally.
///
/// Deliberately does NOT hold a strong reference to the ReaderViewController
/// (it's only needed during init, to wire up delegate/callbacks) — instead
/// ReaderViewController holds *this* coordinator strongly (see its
/// `retainedCoordinator` property), so the coordinator's lifetime is tied
/// directly to the reader screen's lifetime via ARC, with nothing else
/// needing to track when the screen is popped.
final class ReaderCoordinator: ReaderViewControllerDelegate {

    private let translationService: TranslationService
    private let dictionaryStore: DictionaryStore
    private let progressStore: ReadingProgressStore
    private let libraryBook: LibraryBook
    private weak var presentingViewController: UIViewController?

    init(
        readerViewController: ReaderViewController,
        translationService: TranslationService,
        dictionaryStore: DictionaryStore,
        progressStore: ReadingProgressStore,
        libraryBook: LibraryBook,
        book: EPUBBook,
        presentingViewController: UIViewController
    ) {
        self.translationService = translationService
        self.dictionaryStore = dictionaryStore
        self.progressStore = progressStore
        self.libraryBook = libraryBook
        self.presentingViewController = presentingViewController
        readerViewController.delegate = self

        readerViewController.onProgressChanged = { [progressStore, libraryBook] chapterIndex, fraction in
            progressStore.recordProgress(for: libraryBook, chapterIndex: chapterIndex, scrollFraction: fraction)
        }
        readerViewController.onViewWillDisappear = { [progressStore, libraryBook] chapterIndex, fraction in
            progressStore.flush(for: libraryBook, chapterIndex: chapterIndex, scrollFraction: fraction)
        }

        readerViewController.configure(
            book: book,
            startChapterIndex: min(libraryBook.lastReadChapterIndex, max(book.chapters.count - 1, 0)),
            startPageFraction: libraryBook.lastReadScrollFraction
        )
    }

    // MARK: - ReaderViewControllerDelegate

    func readerDidTapWord(_ word: String, contextSentence: String) {
        let popup = presentPopup()
        popup.showLoading()

        popup.onSaveWord = { [dictionaryStore, libraryBook] word, translation, partOfSpeech, context in
            dictionaryStore.save(
                word: word,
                translation: translation,
                partOfSpeech: partOfSpeech,
                contextSentence: context,
                bookTitle: libraryBook.title
            )
        }

        Task {
            do {
                let result = try await translationService.translateWord(word, contextSentence: contextSentence)
                await MainActor.run {
                    popup.showWordResult(
                        word: result.word,
                        translation: result.translation,
                        partOfSpeech: result.partOfSpeech,
                        contextSentence: contextSentence
                    )
                }
            } catch {
                await MainActor.run {
                    popup.showError(errorMessage(for: error))
                }
            }
        }
    }

    func readerDidRequestSentenceTranslation(_ sentence: String) {
        let popup = presentPopup()
        popup.showLoading()

        Task {
            do {
                let result = try await translationService.translateSentence(sentence)
                await MainActor.run {
                    popup.showSentenceResult(original: result.original, translated: result.translated)
                }
            } catch {
                await MainActor.run {
                    popup.showError(errorMessage(for: error))
                }
            }
        }
    }

    func readerDidTapFootnote(_ footnoteText: String) {
        presentReplacingCurrent(FootnotePopupViewController(text: footnoteText))
    }

    // MARK: - Helpers

    private func presentPopup() -> TranslationPopupViewController {
        let popup = TranslationPopupViewController()
        presentReplacingCurrent(popup)
        return popup
    }

    /// Presents `viewController`, first dismissing whatever's already
    /// presented (if anything) rather than stacking on top of it or letting
    /// UIKit silently no-op the present() call. Shared between the
    /// translation popup and the footnote popup — both are sheets that
    /// should never appear two at once.
    private func presentReplacingCurrent(_ viewController: UIViewController) {
        if let presenter = presentingViewController, presenter.presentedViewController != nil {
            presenter.dismiss(animated: false) {
                presenter.present(viewController, animated: true)
            }
        } else {
            presentingViewController?.present(viewController, animated: true)
        }
    }

    private func errorMessage(for error: Error) -> String {
        switch error {
        case TranslationError.network:
            return "Нет соединения. Проверьте интернет и попробуйте снова."
        case TranslationError.serverError, TranslationError.invalidResponse:
            return "Не удалось получить перевод. Попробуйте ещё раз."
        default:
            return "Что-то пошло не так."
        }
    }
}
