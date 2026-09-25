import UIKit

final class FootnotePopupViewController: UIViewController {

    private let textLabel = UILabel()
    private let footnoteText: String

    init(text: String) {
        self.footnoteText = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSheetPresentation()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        textLabel.text = footnoteText
        textLabel.font = .systemFont(ofSize: 17)
        textLabel.numberOfLines = 0

        view.addSubview(textLabel)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            textLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            textLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    private func setupSheetPresentation() {
        guard let sheet = sheetPresentationController else { return }
        // Footnotes vary a lot in length (one clause vs. several sentences) —
        // .medium/.large rather than a fixed small height like the
        // translation popup, since a long footnote would otherwise get
        // clipped or need its own internal scrolling.
        sheet.detents = [.medium(), .large()]
        sheet.prefersGrabberVisible = true
    }
}
