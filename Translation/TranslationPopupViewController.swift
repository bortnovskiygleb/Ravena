import UIKit

final class TranslationPopupViewController: UIViewController {

    /// Fired when the user taps "Add to dictionary" on a word result.
    /// Actual persistence isn't wired up yet — this is the hook the next step will use.
    var onSaveWord: ((_ word: String, _ translation: String, _ partOfSpeech: String?, _ contextSentence: String) -> Void)?

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let stack = UIStackView()

    // Kept around so the save button knows what to persist.
    private var pendingWordSave: (word: String, translation: String, partOfSpeech: String?, context: String)?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSheetPresentation()
    }

    // MARK: - Public state transitions

    func showLoading() {
        pendingWordSave = nil
        errorLabel.isHidden = true
        saveButton.isHidden = true
        titleLabel.text = nil
        bodyLabel.text = nil
        spinner.startAnimating()
    }

    func showWordResult(word: String, translation: String, partOfSpeech: String?, contextSentence: String) {
        spinner.stopAnimating()
        errorLabel.isHidden = true

        titleLabel.text = word
        var subtitle = translation
        if let partOfSpeech {
            subtitle += "  ·  \(partOfSpeech)"
        }
        bodyLabel.text = subtitle

        pendingWordSave = (word, translation, partOfSpeech, contextSentence)
        saveButton.isHidden = false
    }

    func showSentenceResult(original: String, translated: String) {
        spinner.stopAnimating()
        errorLabel.isHidden = true
        saveButton.isHidden = true

        titleLabel.text = original
        bodyLabel.text = translated
    }

    func showError(_ message: String) {
        spinner.stopAnimating()
        saveButton.isHidden = true
        titleLabel.text = nil
        bodyLabel.text = nil
        errorLabel.text = message
        errorLabel.isHidden = false
    }

    // MARK: - UI setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        titleLabel.font = .boldSystemFont(ofSize: 20)
        titleLabel.numberOfLines = 0

        bodyLabel.font = .systemFont(ofSize: 17)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        errorLabel.font = .systemFont(ofSize: 15)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        saveButton.setTitle("Добавить в словарь", for: .normal)
        saveButton.isHidden = true
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(bodyLabel)
        stack.addArrangedSubview(errorLabel)
        stack.addArrangedSubview(saveButton)

        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    private func setupSheetPresentation() {
        guard let sheet = sheetPresentationController else { return }
        // .small keeps it compact for a single word; sentence results with long
        // translations still fit since the label wraps and the sheet auto-grows
        // via the stack's intrinsic content size up to .medium.
        sheet.detents = [.small(), .medium()]
        if #available(iOS 16.0, *) {
            sheet.selectedDetentIdentifier = .small
        }
        sheet.prefersGrabberVisible = true
    }

    @objc private func saveTapped() {
        guard let pending = pendingWordSave else { return }
        onSaveWord?(pending.word, pending.translation, pending.partOfSpeech, pending.context)

        saveButton.setTitle("Добавлено ✓", for: .normal)
        saveButton.isEnabled = false
    }
}

@available(iOS 16.0, *)
private extension UISheetPresentationController.Detent.Identifier {
    static let small = UISheetPresentationController.Detent.Identifier("small")
}

private extension UISheetPresentationController.Detent {
    static func small() -> UISheetPresentationController.Detent {
        if #available(iOS 16.0, *) {
            return .custom(identifier: .small) { _ in 180 }
        }
        return .medium()
    }
}
