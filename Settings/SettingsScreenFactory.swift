import UIKit
import SwiftUI

enum SettingsScreenFactory {
    static func makeViewController() -> UIViewController {
        UIHostingController(rootView: SettingsView(store: ReaderSettingsStore.shared))
    }
}
