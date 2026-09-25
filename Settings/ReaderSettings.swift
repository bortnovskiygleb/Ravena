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
        case system
        case newYork
        case georgia
        case palatino
        case iowan
        case charter
        case baskerville
        case gillSans
        case avenir
        case serif
        case monospaced
        case courierNew

        var displayName: String {
            switch self {
            case .system:      return "Системный"
            case .newYork:     return "New York"
            case .georgia:     return "Georgia"
            case .palatino:    return "Palatino"
            case .iowan:       return "Iowan Old Style"
            case .charter:     return "Charter"
            case .baskerville: return "Baskerville"
            case .gillSans:    return "Gill Sans"
            case .avenir:      return "Avenir"
            case .serif:       return "Системный Serif"
            case .monospaced:  return "Системный Моно"
            case .courierNew:  return "Courier New"
            }
        }

        // MARK: - Font resolution

        func font(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            switch self {
            case .system:
                return .systemFont(ofSize: size, weight: weight)

            case .newYork:
                // New York — Apple's reading-optimised serif, available iOS 13+.
                // The family name "New York" is exposed via UIFont.familyNames; the
                // individual face names depend on the installed variant (Regular /
                // Medium / Semibold / Bold). We ask for the closest match to the
                // requested weight rather than hard-coding a single PostScript name.
                let isBold = weight == .bold || weight == .semibold || weight == .heavy || weight == .black
                let candidate = isBold ? "NewYork-Semibold" : "NewYork-Regular"
                return UIFont(name: candidate, size: size) ?? serifFallback(size: size)

            case .georgia:
                let name = Self.georgiaName(weight: weight, italic: false)
                return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)

            case .palatino:
                let name = Self.palatinoName(weight: weight, italic: false)
                return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)

            case .iowan:
                let name = Self.iowanName(weight: weight, italic: false)
                return UIFont(name: name, size: size) ?? serifFallback(size: size)

            case .charter:
                let name = Self.charterName(weight: weight, italic: false)
                return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)

            case .baskerville:
                let name = Self.baskervilleName(weight: weight, italic: false)
                return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)

            case .gillSans:
                let name = Self.gillSansName(weight: weight, italic: false)
                return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)

            case .avenir:
                let name = Self.avenirName(weight: weight, italic: false)
                return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)

            case .serif:
                return serifFallback(size: size)

            case .monospaced:
                return .monospacedSystemFont(ofSize: size, weight: weight)

            case .courierNew:
                let name = Self.courierNewName(weight: weight, italic: false)
                return UIFont(name: name, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
            }
        }

        /// Variant with explicit italic flag, used by ChapterRenderer for italicBody paragraphs.
        func font(ofSize size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool) -> UIFont {
            guard italic else { return font(ofSize: size, weight: weight) }

            switch self {
            case .system:
                let base = UIFont.systemFont(ofSize: size, weight: weight)
                return base.withTraits(.traitItalic)

            case .newYork:
                let isBold = weight == .bold || weight == .semibold || weight == .heavy || weight == .black
                let candidate = isBold ? "NewYork-SemiboldItalic" : "NewYork-RegularItalic"
                return UIFont(name: candidate, size: size)
                    ?? font(ofSize: size, weight: weight).withTraits(.traitItalic)

            case .georgia:
                return UIFont(name: Self.georgiaName(weight: weight, italic: true), size: size)
                    ?? font(ofSize: size, weight: weight).withTraits(.traitItalic)

            case .palatino:
                return UIFont(name: Self.palatinoName(weight: weight, italic: true), size: size)
                    ?? font(ofSize: size, weight: weight).withTraits(.traitItalic)

            case .iowan:
                return UIFont(name: Self.iowanName(weight: weight, italic: true), size: size)
                    ?? font(ofSize: size, weight: weight).withTraits(.traitItalic)

            case .charter:
                return UIFont(name: Self.charterName(weight: weight, italic: true), size: size)
                    ?? font(ofSize: size, weight: weight).withTraits(.traitItalic)

            case .baskerville:
                return UIFont(name: Self.baskervilleName(weight: weight, italic: true), size: size)
                    ?? font(ofSize: size, weight: weight).withTraits(.traitItalic)

            case .gillSans:
                return UIFont(name: Self.gillSansName(weight: weight, italic: true), size: size)
                    ?? font(ofSize: size, weight: weight).withTraits(.traitItalic)

            case .avenir:
                return UIFont(name: Self.avenirName(weight: weight, italic: true), size: size)
                    ?? font(ofSize: size, weight: weight).withTraits(.traitItalic)

            case .serif:
                return serifFallback(size: size).withTraits(.traitItalic)

            case .monospaced:
                return UIFont.monospacedSystemFont(ofSize: size, weight: weight).withTraits(.traitItalic)

            case .courierNew:
                return UIFont(name: Self.courierNewName(weight: weight, italic: true), size: size)
                    ?? font(ofSize: size, weight: weight).withTraits(.traitItalic)
            }
        }

        // MARK: - PostScript name helpers

        private static func georgiaName(weight: UIFont.Weight, italic: Bool) -> String {
            switch (weight == .bold || weight == .heavy || weight == .black, italic) {
            case (true,  true):  return "Georgia-BoldItalic"
            case (true,  false): return "Georgia-Bold"
            case (false, true):  return "Georgia-Italic"
            case (false, false): return "Georgia"
            }
        }

        private static func palatinoName(weight: UIFont.Weight, italic: Bool) -> String {
            switch (weight == .bold || weight == .heavy || weight == .black, italic) {
            case (true,  true):  return "Palatino-BoldItalic"
            case (true,  false): return "Palatino-Bold"
            case (false, true):  return "Palatino-Italic"
            case (false, false): return "Palatino-Roman"
            }
        }

        private static func iowanName(weight: UIFont.Weight, italic: Bool) -> String {
            // Iowan Old Style ships as part of the iOS system font library.
            switch (weight == .bold || weight == .heavy || weight == .black, italic) {
            case (true,  true):  return "IowanOldStyle-BoldItalic"
            case (true,  false): return "IowanOldStyle-Bold"
            case (false, true):  return "IowanOldStyle-Italic"
            case (false, false): return "IowanOldStyle-Roman"
            }
        }

        private static func charterName(weight: UIFont.Weight, italic: Bool) -> String {
            switch (weight == .bold || weight == .heavy || weight == .black, italic) {
            case (true,  true):  return "Charter-BoldItalic"
            case (true,  false): return "Charter-Bold"
            case (false, true):  return "Charter-Italic"
            case (false, false): return "Charter-Roman"
            }
        }

        private static func baskervilleName(weight: UIFont.Weight, italic: Bool) -> String {
            switch (weight == .bold || weight == .heavy || weight == .black, italic) {
            case (true,  true):  return "Baskerville-BoldItalic"
            case (true,  false): return "Baskerville-Bold"
            case (false, true):  return "Baskerville-Italic"
            case (false, false): return "Baskerville"
            }
        }

        private static func gillSansName(weight: UIFont.Weight, italic: Bool) -> String {
            switch (weight == .bold || weight == .heavy || weight == .black, italic) {
            case (true,  true):  return "GillSans-BoldItalic"
            case (true,  false): return "GillSans-Bold"
            case (false, true):  return "GillSans-Italic"
            case (false, false): return "GillSans"
            }
        }

        private static func avenirName(weight: UIFont.Weight, italic: Bool) -> String {
            // Avenir doesn't have a true italic — "Oblique" is used instead.
            switch (weight == .bold || weight == .heavy || weight == .black, italic) {
            case (true,  true):  return "Avenir-HeavyOblique"
            case (true,  false): return "Avenir-Heavy"
            case (false, true):  return "Avenir-BookOblique"
            case (false, false): return "Avenir-Book"
            }
        }

        private static func courierNewName(weight: UIFont.Weight, italic: Bool) -> String {
            switch (weight == .bold || weight == .heavy || weight == .black, italic) {
            case (true,  true):  return "CourierNewPS-BoldItalicMT"
            case (true,  false): return "CourierNewPS-BoldMT"
            case (false, true):  return "CourierNewPS-ItalicMT"
            case (false, false): return "CourierNewPSMT"
            }
        }

        private func serifFallback(size: CGFloat) -> UIFont {
            let base = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            let descriptor = base.withDesign(.serif) ?? base
            return UIFont(descriptor: descriptor, size: size)
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
