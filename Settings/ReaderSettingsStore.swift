import Foundation
import Combine

/// A single shared instance so that changing a setting in the Settings screen
/// is immediately reflected in any open reader screen, without manual wiring
/// between the two.
final class ReaderSettingsStore: ObservableObject {

    static let shared = ReaderSettingsStore()

    @Published var settings: ReaderSettings {
        didSet { persist() }
    }

    private let defaultsKey = "reader.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data) {
            settings = decoded.clamped()
        } else {
            settings = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
