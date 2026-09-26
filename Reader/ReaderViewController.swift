import UIKit
import SwiftUI
import Combine

protocol ReaderViewControllerDelegate: AnyObject {
    /// Fired when the user taps a single word.
    func readerDidTapWord(_ word: String, contextSentence: String)
    /// Fired when the user long-presses a word — translates the whole sentence it belongs to.
    func readerDidRequestSentenceTranslation(_ sentence: String)
    /// Fired when the user taps a footnote marker.
    func readerDidTapFootnote(_ footnoteText: String)
}

final class ReaderViewController: UIViewController {

    weak var delegate: ReaderViewControllerDelegate?

    /// Purely for retention. ReaderCoordinator sets itself as `delegate`
    /// above (a weak reference) but doesn't hold this view controller
    /// strongly — something still needs to keep the coordinator alive for as
    /// long as this screen exists. Storing it here means that happens
    /// automatically: the moment this view controller is deallocated (popped
    /// off the navigation stack, replaced, whatever), ARC releases the
    /// coordinator along with it. Whoever creates the coordinator should
    /// assign it here instead of holding it in a side-channel property of
    /// their own.
    var retainedCoordinator: AnyObject?

    /// Fired after each page turn, with the current chapter index and how far
    /// through that chapter (by page count) the user is, 0...1.
    var onProgressChanged: ((_ chapterIndex: Int, _ pageFraction: Double) -> Void)?

    /// Fired right before the screen disappears — persist immediately here
    /// rather than relying only on onProgressChanged.
    var onViewWillDisappear: ((_ chapterIndex: Int, _ pageFraction: Double) -> Void)?

    private var book: EPUBBook!
    private var currentChapterIndex = 0
    private var pendingStart: (chapterIndex: Int, fraction: Double)?

    /// Paginating a chapter is real work (lays out the whole chapter via TextKit),
    /// so results are cached per chapter index and only thrown away when
    /// something that affects layout changes (font settings, view size).
    private var pagesByChapter: [Int: ChapterPagination] = [:]

    private let progressBar = ReadingProgressBar()
    private lazy var pageViewController = UIPageViewController(
        transitionStyle: .pageCurl,
        navigationOrientation: .horizontal,
        options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue]
    )

    private let previousChapterButton = UIBarButtonItem()
    private let nextChapterButton = UIBarButtonItem()
    private var cancellables = Set<AnyCancellable>()

    /// True while this view controller is on screen. Tracked manually via
    /// viewWillAppear / viewWillDisappear so repaginate knows whether it can
    /// apply changes immediately or must defer them to the next appearance.
    private var isVisible = false

    /// Non-nil when a settings change happened while the reader was off-screen.
    /// Stores the fractional position (0...1 within the current chapter) so
    /// viewWillAppear can rebuild at the right spot instead of calling
    /// setViewControllers while UIPageViewController's view is off-screen,
    /// which can silently fail to update viewControllers?.first and then cause
    /// the current chapter to keep displaying the old font.
    private var deferredRepaginationFraction: Double?

    /// Tapping empty space toggles this — hides the progress label, the
    /// navigation bar (with its TOC/chapter buttons), and the system status
    /// bar, for an uncluttered full-screen reading view.
    private var isChromeHidden = false

    // MARK: - Public API

    /// Call once, right after creating the view controller. Actual pagination
    /// is deferred until the view has a real size (see viewDidLayoutSubviews).
    func configure(book: EPUBBook, startChapterIndex: Int, startPageFraction: Double) {
        self.book = book
        pendingStart = (startChapterIndex, startPageFraction)
        view.setNeedsLayout()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPageViewController()
        setupNavigationBar()
        observeSettingsChanges()
    }

    override var prefersStatusBarHidden: Bool { isChromeHidden }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .slide }

    /// Hides/shows the progress label, navigation bar, and system status bar
    /// together — tapping anywhere on the page that isn't a word or a
    /// footnote marker triggers this (see pageDidTapEmptySpace).
    private func toggleChromeVisibility() {
        isChromeHidden.toggle()
        navigationController?.setNavigationBarHidden(isChromeHidden, animated: true)

        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(isChromeHidden, animated: true)
        } else {
            if !isChromeHidden {
                tabBarController?.tabBar.isHidden = false
            }
            UIView.animate(withDuration: 0.25, animations: {
                self.tabBarController?.tabBar.alpha = self.isChromeHidden ? 0 : 1
            }, completion: { _ in
                if self.isChromeHidden {
                    self.tabBarController?.tabBar.isHidden = true
                }
            })
        }

        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard book != nil else { return }
        if let start = pendingStart {
            pendingStart = nil
            openAtStart(chapterIndex: start.chapterIndex, fraction: start.fraction)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        guard book != nil else { return }

        if let fraction = deferredRepaginationFraction {
            // Settings changed while we were off-screen — run the repagination
            // now that the view is about to become visible, so setViewControllers
            // fires while UIPageViewController's view is properly in the window.
            deferredRepaginationFraction = nil
            pageViewController.dataSource = nil
            openAtStart(chapterIndex: currentChapterIndex, fraction: fraction)
            pageViewController.dataSource = self
            return
        }

        // Normal re-seat: UIPageViewController can fail to visually refresh a
        // setViewControllers call that happened while its view was off-screen.
        guard let current = pageViewController.viewControllers?.first as? ReaderPageViewController else { return }
        if let page = makePage(chapterIndex: current.chapterIndex, pageIndex: current.pageIndex) {
            pageViewController.setViewControllers([page], direction: .forward, animated: false)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // Page boundaries depend on the content frame size, so rotation or an
        // iPad Split View resize invalidates all cached pagination, same as a
        // font-size change would.
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.repaginateKeepingRelativePosition()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        guard let current = pageViewController.viewControllers?.first as? ReaderPageViewController else { return }
        onViewWillDisappear?(current.chapterIndex, fraction(chapterIndex: current.chapterIndex, pageIndex: current.pageIndex))
    }

    private var visibleSafeAreaInsets: UIEdgeInsets?

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        // When chrome is fully visible and no compensation is active,
        // record the baseline safe-area insets the text layout expects.
        if !isChromeHidden && additionalSafeAreaInsets == .zero {
            visibleSafeAreaInsets = view.safeAreaInsets
            return
        }

        // While chrome is hidden — or during the show/hide animation while
        // additionalSafeAreaInsets haven't yet reached .zero — compensate so
        // the effective safe area stays equal to the recorded baseline.
        // This prevents the page-view from resizing (and re-laying-out text)
        // during the navigation-bar animation, eliminating text jitter.
        guard let visible = visibleSafeAreaInsets else { return }

        let systemInsets = UIEdgeInsets(
            top: view.safeAreaInsets.top - additionalSafeAreaInsets.top,
            left: view.safeAreaInsets.left - additionalSafeAreaInsets.left,
            bottom: view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom,
            right: view.safeAreaInsets.right - additionalSafeAreaInsets.right
        )

        let neededInsets = UIEdgeInsets(
            top: max(0, visible.top - systemInsets.top),
            left: max(0, visible.left - systemInsets.left),
            bottom: max(0, visible.bottom - systemInsets.bottom),
            right: max(0, visible.right - systemInsets.right)
        )

        if additionalSafeAreaInsets != neededInsets {
            additionalSafeAreaInsets = neededInsets
        }
    }

    // MARK: - Setup

    private func setupPageViewController() {
        addChild(pageViewController)
        view.addSubview(progressBar)
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)
        pageViewController.dataSource = self
        pageViewController.delegate = self

        progressBar.translatesAutoresizingMaskIntoConstraints = false
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            progressBar.topAnchor.constraint(equalTo: pageViewController.view.bottomAnchor),
            progressBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func setupNavigationBar() {
        let contentsButton = UIBarButtonItem(
            image: UIImage(systemName: "list.bullet"),
            style: .plain,
            target: self,
            action: #selector(contentsButtonTapped)
        )
        navigationItem.leftBarButtonItem = contentsButton

        previousChapterButton.image = UIImage(systemName: "chevron.left")
        previousChapterButton.target = self
        previousChapterButton.action = #selector(previousChapterButtonTapped)

        nextChapterButton.image = UIImage(systemName: "chevron.right")
        nextChapterButton.target = self
        nextChapterButton.action = #selector(nextChapterButtonTapped)

        navigationItem.rightBarButtonItems = [nextChapterButton, previousChapterButton]
    }

    private func observeSettingsChanges() {
        let store = ReaderSettingsStore.shared
        view.backgroundColor = store.settings.backgroundTheme.backgroundColor(brightness: store.settings.backgroundBrightness)

        store.$settings
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] newSettings in
                self?.view.backgroundColor = newSettings.backgroundTheme.backgroundColor(brightness: newSettings.backgroundBrightness)
                self?.repaginateKeepingRelativePosition()
            }
            .store(in: &cancellables)
    }

    // MARK: - Pagination

    private var pageContentSize: CGSize {
        let insets = ReaderLayoutMetrics.textInsets(for: ReaderSettingsStore.shared.settings)
        let bounds = pageViewController.view.bounds
        return CGSize(
            width: max(bounds.width - insets.left - insets.right, 0),
            height: max(bounds.height - insets.top - insets.bottom, 0)
        )
    }

    private func pagination(forChapter index: Int) -> ChapterPagination {
        if let cached = pagesByChapter[index] { return cached }
        guard book.chapters.indices.contains(index) else { return ChapterPagination(pages: [], fullText: "", paragraphStartOffsets: []) }
        let result = ChapterPaginator.paginate(
            chapter: book.chapters[index],
            settings: ReaderSettingsStore.shared.settings,
            pageSize: pageContentSize
        )
        pagesByChapter[index] = result
        return result
    }

    private func makePage(chapterIndex: Int, pageIndex: Int) -> ReaderPageViewController? {
        let chapterPagination = pagination(forChapter: chapterIndex)
        guard chapterPagination.pages.indices.contains(pageIndex) else { return nil }
        let paginatedPage = chapterPagination.pages[pageIndex]
        let settings = ReaderSettingsStore.shared.settings
        let page = ReaderPageViewController(
            pageText: paginatedPage.text,
            pageIndex: pageIndex,
            chapterIndex: chapterIndex,
            backgroundColor: settings.backgroundTheme.backgroundColor(brightness: settings.backgroundBrightness),
            textInsets: ReaderLayoutMetrics.textInsets(for: settings),
            chapterFullText: chapterPagination.fullText,
            pageStartOffset: paginatedPage.startOffset
        )
        page.delegate = self
        return page
    }

    private func fraction(chapterIndex: Int, pageIndex: Int) -> Double {
        let total = pagination(forChapter: chapterIndex).pages.count
        return total > 1 ? Double(pageIndex) / Double(total - 1) : 0
    }

    private func updateProgressBar(chapterIndex: Int, pageIndex: Int, animated: Bool) {
        let totalPages = pagination(forChapter: chapterIndex).pages.count
        progressBar.update(currentPageIndex: pageIndex, totalPages: totalPages, animated: animated)
    }

    private func openAtStart(chapterIndex: Int, fraction: Double) {
        let clampedChapter = max(0, min(chapterIndex, book.chapters.count - 1))
        let chapterPages = pagination(forChapter: clampedChapter).pages
        let pageIndex = chapterPages.isEmpty
            ? 0
            : min(Int((fraction * Double(max(chapterPages.count - 1, 0))).rounded()), chapterPages.count - 1)

        guard let page = makePage(chapterIndex: clampedChapter, pageIndex: pageIndex) else { return }
        currentChapterIndex = clampedChapter
        pageViewController.setViewControllers([page], direction: .forward, animated: false)
        updateChapterNavButtons()
        updateProgressBar(chapterIndex: clampedChapter, pageIndex: pageIndex, animated: false)
    }

    /// Used whenever pagination must be redone (font/background change, size
    /// change): remembers roughly where the user was (as a fraction through
    /// the current chapter) and re-opens at the equivalent spot in the newly
    /// paginated chapter, since exact page indices don't carry over.
    ///
    /// When the reader is not on screen (e.g. the user is on the Settings tab),
    /// UIPageViewController's setViewControllers can silently fail to update
    /// viewControllers?.first. A subsequent viewWillAppear then rebuilds the
    /// page using a stale pageIndex from the old VC — which may be out of range
    /// in the new pagination — so makePage returns nil and the current chapter
    /// keeps the old font. To avoid this, we defer the actual rebuild to
    /// viewWillAppear when the view is not currently visible.
    private func repaginateKeepingRelativePosition() {
        guard book != nil else { return }

        // Capture the position BEFORE clearing the cache: fraction() relies on
        // pagesByChapter still containing the old pagination.
        let fractionBeforeChange: Double
        if let current = pageViewController.viewControllers?.first as? ReaderPageViewController {
            fractionBeforeChange = fraction(chapterIndex: current.chapterIndex, pageIndex: current.pageIndex)
        } else {
            fractionBeforeChange = 0
        }

        pagesByChapter.removeAll()

        guard isVisible else {
            // Off-screen: stash the position and let viewWillAppear do the
            // actual rebuild once the view is properly in the window.
            deferredRepaginationFraction = fractionBeforeChange
            return
        }

        // On-screen: apply immediately. Nil the dataSource first so
        // UIPageViewController discards any prefetched neighbouring pages it's
        // holding; without this, swipe-to-next after a font change shows a
        // stale page that was pre-built before the repagination.
        pageViewController.dataSource = nil
        openAtStart(chapterIndex: currentChapterIndex, fraction: fractionBeforeChange)
        pageViewController.dataSource = self
    }

    // MARK: - Chapter navigation

    /// Which page (within the chapter's own pagination) contains the start
    /// of the given paragraph — used to jump a TOC entry to the exact spot
    /// it targets rather than just the chapter's first page.
    private func pageIndex(forParagraph paragraphIndex: Int, in chapterIndex: Int) -> Int {
        let chapterPagination = pagination(forChapter: chapterIndex)
        guard chapterPagination.paragraphStartOffsets.indices.contains(paragraphIndex) else { return 0 }
        let targetOffset = chapterPagination.paragraphStartOffsets[paragraphIndex]

        // Pages are in increasing startOffset order, so the last one whose
        // startOffset doesn't exceed the target is the one containing it.
        var result = 0
        for (index, page) in chapterPagination.pages.enumerated() {
            if page.startOffset <= targetOffset {
                result = index
            } else {
                break
            }
        }
        return result
    }

    private func goToChapter(_ chapterIndex: Int, paragraphIndex: Int = 0) {
        guard book.chapters.indices.contains(chapterIndex) else { return }
        let targetPageIndex = pageIndex(forParagraph: paragraphIndex, in: chapterIndex)
        guard let page = makePage(chapterIndex: chapterIndex, pageIndex: targetPageIndex) else { return }
        let direction: UIPageViewController.NavigationDirection = chapterIndex > currentChapterIndex ? .forward : .reverse
        pageViewController.setViewControllers([page], direction: direction, animated: true) { [weak self] _ in
            guard let self else { return }
            self.currentChapterIndex = chapterIndex
            self.updateChapterNavButtons()
            let newFraction = self.fraction(chapterIndex: chapterIndex, pageIndex: targetPageIndex)
            self.updateProgressBar(chapterIndex: chapterIndex, pageIndex: targetPageIndex, animated: false)
            self.onProgressChanged?(chapterIndex, newFraction)
        }
    }

    private func updateChapterNavButtons() {
        previousChapterButton.isEnabled = currentChapterIndex > 0
        nextChapterButton.isEnabled = currentChapterIndex < book.chapters.count - 1
    }

    @objc private func contentsButtonTapped() {
        let tocView = TableOfContentsView(
            entries: book.tableOfContents,
            currentChapterIndex: currentChapterIndex
        ) { [weak self] selectedEntry in
            self?.dismiss(animated: true) {
                self?.goToChapter(selectedEntry.chapterIndex, paragraphIndex: selectedEntry.paragraphIndex)
            }
        }
        present(UIHostingController(rootView: tocView), animated: true)
    }

    @objc private func previousChapterButtonTapped() {
        goToChapter(currentChapterIndex - 1)
    }

    @objc private func nextChapterButtonTapped() {
        goToChapter(currentChapterIndex + 1)
    }
}

// MARK: - UIPageViewControllerDataSource — crosses chapter boundaries transparently

extension ReaderViewController: UIPageViewControllerDataSource {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerBefore viewController: UIViewController
    ) -> UIViewController? {
        guard let current = viewController as? ReaderPageViewController else { return nil }

        if current.pageIndex > 0 {
            return makePage(chapterIndex: current.chapterIndex, pageIndex: current.pageIndex - 1)
        }
        var previousChapterIndex = current.chapterIndex - 1
        while previousChapterIndex >= 0 {
            let previousPages = pagination(forChapter: previousChapterIndex).pages
            if let lastPageIndex = previousPages.indices.last {
                return makePage(chapterIndex: previousChapterIndex, pageIndex: lastPageIndex)
            }
            previousChapterIndex -= 1
        }
        return nil
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        viewControllerAfter viewController: UIViewController
    ) -> UIViewController? {
        guard let current = viewController as? ReaderPageViewController else { return nil }

        let chapterPages = pagination(forChapter: current.chapterIndex).pages
        if current.pageIndex + 1 < chapterPages.count {
            return makePage(chapterIndex: current.chapterIndex, pageIndex: current.pageIndex + 1)
        }
        var nextChapterIndex = current.chapterIndex + 1
        while book.chapters.indices.contains(nextChapterIndex) {
            let nextPages = pagination(forChapter: nextChapterIndex).pages
            if !nextPages.isEmpty {
                return makePage(chapterIndex: nextChapterIndex, pageIndex: 0)
            }
            nextChapterIndex += 1
        }
        return nil
    }
}

// MARK: - UIPageViewControllerDelegate

extension ReaderViewController: UIPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        guard completed, let current = pageViewController.viewControllers?.first as? ReaderPageViewController else { return }
        currentChapterIndex = current.chapterIndex
        updateChapterNavButtons()
        let newFraction = fraction(chapterIndex: current.chapterIndex, pageIndex: current.pageIndex)
        updateProgressBar(chapterIndex: current.chapterIndex, pageIndex: current.pageIndex, animated: false)
        onProgressChanged?(current.chapterIndex, newFraction)
    }
}

// MARK: - ReaderPageViewControllerDelegate

extension ReaderViewController: ReaderPageViewControllerDelegate {
    func pageDidTapWord(_ word: String, contextSentence: String) {
        delegate?.readerDidTapWord(word, contextSentence: contextSentence)
    }

    func pageDidRequestSentenceTranslation(_ sentence: String) {
        delegate?.readerDidRequestSentenceTranslation(sentence)
    }

    func pageDidTapFootnote(_ footnoteText: String) {
        delegate?.readerDidTapFootnote(footnoteText)
    }

    func pageDidTapEmptySpace() {
        toggleChromeVisibility()
    }
}
