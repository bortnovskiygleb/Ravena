import UIKit

protocol ReaderPageViewControllerDelegate: AnyObject {
    func pageDidTapWord(_ word: String, contextSentence: String)
    func pageDidRequestSentenceTranslation(_ sentence: String)
    func pageDidTapFootnote(_ footnoteText: String)
    /// Fired when a tap lands somewhere that isn't a word or a footnote
    /// marker (whitespace, punctuation, margin) — used to toggle the
    /// reader's chrome (progress label, nav bar, status bar) in and out of view.
    func pageDidTapEmptySpace()
}

final class ReaderPageViewController: UIViewController {

    weak var delegate: ReaderPageViewControllerDelegate?

    /// Position within its chapter — the parent (ReaderViewController) reads
    /// these off the currently visible page to track and persist progress.
    let pageIndex: Int
    let chapterIndex: Int

    private let pageText: NSAttributedString
    private let textInsets: UIEdgeInsets
    private let chapterFullText: String
    private let pageStartOffset: Int
    private let textView = UITextView()

    init(
        pageText: NSAttributedString,
        pageIndex: Int,
        chapterIndex: Int,
        backgroundColor: UIColor,
        textInsets: UIEdgeInsets,
        chapterFullText: String,
        pageStartOffset: Int
    ) {
        self.pageText = pageText
        self.pageIndex = pageIndex
        self.chapterIndex = chapterIndex
        self.textInsets = textInsets
        self.chapterFullText = chapterFullText
        self.pageStartOffset = pageStartOffset
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = backgroundColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTextView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // A page is normally paginated to fit its frame exactly, so scrolling
        // is never needed. The one exception is ChapterPaginator's emergency
        // fallback (an unbreakable line forced a taller-than-normal container)
        // — detect that by comparing measured content size to the actual frame,
        // and allow scrolling just for this one page so the overflow stays
        // reachable instead of being silently clipped.
        let fitsWithoutScrolling = textView.contentSize.height <= textView.bounds.height + 1
        textView.isScrollEnabled = !fitsWithoutScrolling
    }

    private func setupTextView() {
        textView.attributedText = pageText
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = false // default; viewDidLayoutSubviews may flip this on for the rare overflow case
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = .clear
        textView.dataDetectorTypes = []
        textView.textContainerInset = textInsets
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInsetAdjustmentBehavior = .never

        view.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        tap.require(toFail: longPress)
        textView.addGestureRecognizer(tap)
        textView.addGestureRecognizer(longPress)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: textView)

        if let footnoteText = footnoteText(at: point) {
            delegate?.pageDidTapFootnote(footnoteText)
            return
        }

        if let hit = wordAndSentence(at: point) {
            delegate?.pageDidTapWord(hit.text, contextSentence: hit.sentence)
        } else {
            delegate?.pageDidTapEmptySpace()
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        guard let hit = wordAndSentence(at: gesture.location(in: textView)) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        delegate?.pageDidRequestSentenceTranslation(hit.sentence)
    }

    /// The superscript footnote marker is small — a tap can land either
    /// right on its character or one position past it, so both are checked.
    private func footnoteText(at point: CGPoint) -> String? {
        guard let position = textView.closestPosition(to: point) else { return nil }
        let offset = textView.offset(from: textView.beginningOfDocument, to: position)
        guard let attributedText = textView.attributedText, attributedText.length > 0 else { return nil }

        for candidate in [offset, offset - 1] where candidate >= 0 && candidate < attributedText.length {
            if let footnote = attributedText.attribute(.footnoteText, at: candidate, effectiveRange: nil) as? String {
                return footnote
            }
        }
        return nil
    }

    private func wordAndSentence(at point: CGPoint) -> (text: String, sentence: String)? {
        guard let tapPosition = textView.closestPosition(to: point) else { return nil }
        guard let wordRange = textView.tokenizer.rangeEnclosingPosition(
            tapPosition, with: .word, inDirection: .layout(.right)
        ) else { return nil }
        guard let word = textView.text(in: wordRange), !word.isEmpty else { return nil }

        // Sentence lookup runs against the *whole chapter's* text, not just this
        // page's — a page-local offset alone can't see a sentence that continues
        // past this page's end. Converting to a chapter-wide offset first (by
        // adding pageStartOffset) is what makes that possible; both offsets are
        // UTF-16/NSString-based, so they're directly additive.
        let localUTF16Offset = textView.offset(from: textView.beginningOfDocument, to: wordRange.start)
        let chapterUTF16Offset = pageStartOffset + localUTF16Offset
        let sentence = SentenceExtractor.sentence(containingUTF16Offset: chapterUTF16Offset, in: chapterFullText) ?? word

        return (word, sentence)
    }
}
