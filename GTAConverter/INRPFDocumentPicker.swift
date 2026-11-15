import SwiftUI
import UniformTypeIdentifiers

/// Uses SwiftUI's native document importer so presentation and provider hand-off
/// are managed by the system rather than a hidden UIKit presenter.
extension View {
    func inrpfDocumentPicker(
        isPresented: Binding<Bool>,
        contentTypes: [UTType],
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[URL], Error>) -> Void,
        onCancellation: @escaping () -> Void = {}
    ) -> some View {
        fileImporter(
            isPresented: isPresented,
            allowedContentTypes: contentTypes,
            allowsMultipleSelection: allowsMultipleSelection
        ) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty else {
                    onCompletion(.failure(NSError(
                        domain: "INRPF.DocumentImport",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "لم يُرجع مستورد الملفات أي عنصر."]
                    )))
                    return
                }
                onCompletion(.success(urls))
            case .failure(let error):
                if error is CancellationError {
                    onCancellation()
                } else {
                    onCompletion(.failure(error))
                }
            }
        }
    }
}
