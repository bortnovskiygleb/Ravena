import UIKit

struct ReaderSettings: Codable, Equatable {
    var fontSize: Double
    var fontStyle: FontStyle
    var backgroundTheme: BackgroundTheme
    var appTheme: AppTheme
    /// Left/right page margin, in points. Top/bottom stay fixed at 16 —
    /// only side margins are exposed, matching the classic e-reader convention.
    var horizontalMargin: Double
    /// Extra space between lines, in points, on top of the font's natural leading.
    var lineSpacing: Double
    /// Brightness adjustment applied to the sepia/night backgrounds, -1
    /// (darker) ... 1 (lighter), 0 = the theme's own default shade. Has no
    /// effect on white/black — those are already at their natural extremes,
    /// adjusting them wouldn't mean anything.
    var backgroundBrightness: Double

    static let `default` = ReaderSettings(
        fontSize: 18,
        fontStyle: .system,
        backgroundTheme: .white,
        appTheme: .system,
        horizontalMargin: 20,
        lineSpacing: 4,
        backgroundBrightness: 0
    )

    /// Single source of truth for the settings sliders' bounds. Margin and
    /// line-spacing stay conservative since they have no real accessibility
    /// upside beyond a point. Font size's upper bound is looser than that
    /// reasoning alone would suggest — larger text is a real accessibility
    /// need — because ChapterPaginator has its own emergency-growth fallback
    /// for a page that doesn't fit at the chosen size, so this range isn't
    /// the only thing standing between a large font and losing chapter text.
    enum Range {
        static let fontSize: ClosedRange<Double> = 14...48
        static let horizontalMargin: ClosedRange<Double> = 8...40
        static let lineSpacing: ClosedRange<Double> = 0...10
        static let backgroundBrightness: ClosedRange<Double> = -1...1
    }

    /// Clamps every bounded field into its valid Range. Applied when settings
    /// are loaded from disk, so a value saved under a wider range in a past
    /// version of the app (before these bounds were tightened) can't silently
    /// stay out-of-range forever.
    func clamped() -> ReaderSettings {
        var copy = self
        copy.fontSize = Range.fontSize.clamping(fontSize)
        copy.horizontalMargin = Range.horizontalMargin.clamping(horizontalMargin)
        copy.lineSpacing = Range.lineSpacing.clamping(lineSpacing)
        copy.backgroundBrightness = Range.backgroundBrightness.clamping(backgroundBrightness)
        return copy
    }

    enum FontStyle: String, Codable, CaseIterable {
        case system, serif, monospaced

        var displayName: String {
            switch self {
            case .system: return "Обычный"
            case .serif: return "С засечками"
            case .monospaced: return "Моно"
            }
        }

        func font(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            switch self {
            case .system:
                return .systemFont(ofSize: size, weight: weight)
            case .serif:
                let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
                let descriptor = base.withDesign(.serif) ?? base
                return UIFont(descriptor: descriptor, size: size)
            case .monospaced:
                return .monospacedSystemFont(ofSize: size, weight: weight)
            }
        }
    }

    enum BackgroundTheme: String, Codable, CaseIterable {
        case white, sepia, night, black

        var displayName: String {
            switch self {
            case .white: return "Белый"
            case .sepia: return "Сепия"
            case .night: return "Ночной"
            case .black: return "Чёрный"
            }
        }

        /// Classic e-reader palettes — sepia and night reduce eye strain versus pure white/black.
        var backgroundColor: UIColor {
            switch self {
            case .white: return .white
            case .sepia: return UIColor(red: 0.96, green: 0.92, blue: 0.82, alpha: 1)
            case .night: return UIColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1)
            case .black: return .black
            }
        }

        /// `brightness` is -1...1 (see ReaderSettings.backgroundBrightness) —
        /// only sepia/night respond to it; white/black are already at their
        /// natural extremes and are returned unchanged regardless of the
        /// value passed in.
        func backgroundColor(brightness: Double) -> UIColor {
            guard self == .sepia || self == .night else { return backgroundColor }

            var hue: CGFloat = 0, saturation: CGFloat = 0, baseBrightness: CGFloat = 0, alpha: CGFloat = 0
            backgroundColor.getHue(&hue, saturation: &saturation, brightness: &baseBrightness, alpha: &alpha)

            // ±0.35 keeps both ends of the slider readable against this
            // theme's fixed text color — going further would eventually wash
            // out (too light) or crush (too dark) into the text color itself.
            let adjusted = baseBrightness + CGFloat(brightness) * 0.35
            let clamped = min(max(adjusted, 0.05), 0.95)
            return UIColor(hue: hue, saturation: saturation, brightness: clamped, alpha: alpha)
        }

        var textColor: UIColor {
            switch self {
            case .white: return .black
            case .sepia: return UIColor(red: 0.25, green: 0.2, blue: 0.12, alpha: 1)
            case .night: return UIColor(white: 0.85, alpha: 1)
            case .black: return UIColor(white: 0.9, alpha: 1)
            }
        }
    }

    enum AppTheme: String, Codable, CaseIterable {
        case system, light, dark

        var displayName: String {
            switch self {
            case .system: return "Системная"
            case .light: return "Светлая"
            case .dark: return "Тёмная"
            }
        }

        var userInterfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .system: return .unspecified
            case .light: return .light
            case .dark: return .dark
            }
        }
    }
}

private extension ClosedRange where Bound == Double {
    func clamping(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}
