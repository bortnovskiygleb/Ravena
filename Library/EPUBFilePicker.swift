import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct EPUBFilePicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // EPUB's registered UTI is "org.idpf.epub-container", but relying purely
        // on filename extension is more forgiving of how third-party apps (Files,
        // cloud storage providers) tag the file.
        let epubType = UTType(filenameExtension: "epub") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [epubType])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
