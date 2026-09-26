import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ReaderSettingsStore

    var body: some View {
        Form {
            Section("Шрифт") {
                HStack {
                    Text("A").font(.footnote).foregroundStyle(.secondary)
                    Slider(value: $store.settings.fontSize, in: ReaderSettings.Range.fontSize, step: 1)
                    Text("A").font(.title3).foregroundStyle(.secondary)
                }

                Text("Пример текста для предпросмотра.")
                    .font(previewFont)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)

                Picker("Стиль", selection: $store.settings.fontStyle) {
                    ForEach(ReaderSettings.FontStyle.allCases, id: \.self) { style in
                        Text(style.displayName)
                            // Fixed size so the wheel row height doesn't change
                            // when the user drags the font-size slider.
                            .font(Font(style.font(ofSize: 17)))
                            .tag(style)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 140)
            }

            Section("Фон для чтения") {
                Picker("Фон", selection: $store.settings.backgroundTheme) {
                    ForEach(ReaderSettings.BackgroundTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                if store.settings.backgroundTheme == .sepia || store.settings.backgroundTheme == .night {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Яркость фона")
                            Spacer()
                            Text(brightnessLabel)
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $store.settings.backgroundBrightness, in: ReaderSettings.Range.backgroundBrightness, step: 0.05)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Тема приложения") {
                Picker("Тема", selection: $store.settings.appTheme) {
                    ForEach(ReaderSettings.AppTheme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Поля и интервалы") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Поля по краям")
                        Spacer()
                        Text("\(Int(store.settings.horizontalMargin)) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.settings.horizontalMargin, in: ReaderSettings.Range.horizontalMargin, step: 2)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Межстрочный интервал")
                        Spacer()
                        Text("\(Int(store.settings.lineSpacing)) pt")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $store.settings.lineSpacing, in: ReaderSettings.Range.lineSpacing, step: 1)
                }
                .padding(.vertical, 2)

                marginPreview
            }
        }
        // On iPad, a Form defaults to spanning the full screen width, which
        // stretches UISegmentedControl's segments proportionally — on a wide
        // iPad in landscape this looks distorted (huge, unevenly-weighted
        // segments). Apple's own Settings app caps its detail panes at a
        // comfortable reading width instead of letting them fill the screen;
        // doing the same here fixes the segmented controls at the source
        // rather than restyling each one individually. No-op on iPhone, since
        // 600pt exceeds every iPhone's width anyway.
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, alignment: .center)
        .navigationTitle("Настройки")
    }

    /// A miniature mock of an actual reading page — the real margin/line-spacing
    /// values are in points meant for a full-size page, so this scales them down
    /// (halved) to stay proportionate inside a small preview box, rather than
    /// showing the literal pt values which would look almost unchanged at this size.
    private var marginPreview: some View {
        Text("Пример текста для предпросмотра полей и межстрочного интервала на странице чтения.")
            .font(previewFont)
            .lineSpacing(CGFloat(store.settings.lineSpacing))
            .foregroundStyle(Color(store.settings.backgroundTheme.textColor))
            .padding(.horizontal, CGFloat(store.settings.horizontalMargin) / 2)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(store.settings.backgroundTheme.backgroundColor(brightness: store.settings.backgroundBrightness)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var brightnessLabel: String {
        let percent = Int((store.settings.backgroundBrightness * 100).rounded())
        if percent == 0 { return "Обычная" }
        return percent > 0 ? "+\(percent)%" : "\(percent)%"
    }

    private var previewFont: Font {
        Font(store.settings.fontStyle.font(ofSize: CGFloat(store.settings.fontSize)))
    }
}
