import UIKit

final class ReadingProgressBar: UIView {

    private let statusLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// `currentPageIndex` and `totalPages` describe position within the
    /// *current chapter* (matching the rest of ReaderViewController's
    /// progress model) — the label shows how many pages are left until the
    /// end of this chapter, not the whole book. `animated` is unused now
    /// that there's no progress bar to animate, kept so call sites don't
    /// need to change.
    func update(currentPageIndex: Int, totalPages: Int, animated: Bool) {
        let remaining = max(totalPages - currentPageIndex - 1, 0)
        // "стр." (abbreviation) rather than spelling out "страница/страницы/
        // страниц" sidesteps Russian's three-way plural agreement entirely —
        // the abbreviated form doesn't decline, so it's correct for any N.
        statusLabel.text = remaining == 0 ? "Последняя страница" : "Осталось \(remaining) стр."
    }

    private func setup() {
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.text = " " // Dummy text to establish height before first update

        addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }
}
