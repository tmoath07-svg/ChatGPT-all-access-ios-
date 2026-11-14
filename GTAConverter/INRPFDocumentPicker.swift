import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Native iOS document picker shared by the main importer and GitHub upload flow.
/// Uses UIKit's delegate callback so a selected URL is delivered explicitly to the app.
struct INRPFDocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onCompletion: (Result<[URL], Error>) -> Void
    let onCancellation: () -> Void

    init(
        contentTypes: [UTType],
        allowsMultipleSelection: Bool,
        onCompletion: @escaping (Result<[URL], Error>) -> Void,
        onCancellation: @escaping () -> Void = {}
    ) {
        self.contentTypes = contentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onCompletion = onCompletion
        self.onCancellation = onCancellation
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion, onCancellation: onCancellation)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onCompletion: (Result<[URL], Error>) -> Void
        private let onCancellation: () -> Void

        init(
            onCompletion: @escaping (Result<[URL], Error>) -> Void,
            onCancellation: @escaping () -> Void
        ) {
            self.onCompletion = onCompletion
            self.onCancellation = onCancellation
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onCompletion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancellation()
        }
    }
}
