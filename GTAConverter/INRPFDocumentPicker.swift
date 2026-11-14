import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Presents the system document picker from a real UIKit presenter.
/// The coordinator is refreshed on every SwiftUI update so callbacks never go stale.
struct INRPFDocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let contentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onCompletion: (Result<[URL], Error>) -> Void
    let onCancellation: () -> Void

    init(
        isPresented: Binding<Bool>,
        contentTypes: [UTType],
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[URL], Error>) -> Void,
        onCancellation: @escaping () -> Void = {}
    ) {
        self._isPresented = isPresented
        self.contentTypes = contentTypes
        self.allowsMultipleSelection = allowsMultipleSelection
        self.onCompletion = onCompletion
        self.onCancellation = onCancellation
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPresented: $isPresented,
            onCompletion: onCompletion,
            onCancellation: onCancellation
        )
    }

    func makeUIViewController(context: Context) -> PickerPresenterController {
        let controller = PickerPresenterController()
        controller.view.backgroundColor = .clear
        controller.onDidAppear = { [weak coordinator = context.coordinator, weak controller] in
            guard let controller else { return }
            coordinator?.presentPicker(
                from: controller,
                contentTypes: self.contentTypes,
                allowsMultipleSelection: self.allowsMultipleSelection
            )
        }
        return controller
    }

    func updateUIViewController(_ controller: PickerPresenterController, context: Context) {
        context.coordinator.update(
            isPresented: $isPresented,
            onCompletion: onCompletion,
            onCancellation: onCancellation
        )
        controller.onDidAppear = { [weak coordinator = context.coordinator, weak controller] in
            guard let controller else { return }
            coordinator?.presentPicker(
                from: controller,
                contentTypes: self.contentTypes,
                allowsMultipleSelection: self.allowsMultipleSelection
            )
        }

        if isPresented {
            context.coordinator.presentPicker(
                from: controller,
                contentTypes: contentTypes,
                allowsMultipleSelection: allowsMultipleSelection
            )
        } else {
            context.coordinator.dismissPickerIfNeeded()
        }
    }

    final class PickerPresenterController: UIViewController {
        var onDidAppear: (() -> Void)?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onDidAppear?()
        }
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private var isPresented: Binding<Bool>
        private var onCompletion: (Result<[URL], Error>) -> Void
        private var onCancellation: () -> Void
        private weak var presenter: PickerPresenterController?
        private var picker: UIDocumentPickerViewController?
        private var isFinishing = false

        init(
            isPresented: Binding<Bool>,
            onCompletion: @escaping (Result<[URL], Error>) -> Void,
            onCancellation: @escaping () -> Void
        ) {
            self.isPresented = isPresented
            self.onCompletion = onCompletion
            self.onCancellation = onCancellation
        }

        func update(
            isPresented: Binding<Bool>,
            onCompletion: @escaping (Result<[URL], Error>) -> Void,
            onCancellation: @escaping () -> Void
        ) {
            self.isPresented = isPresented
            self.onCompletion = onCompletion
            self.onCancellation = onCancellation
        }

        func presentPicker(
            from presenter: PickerPresenterController,
            contentTypes: [UTType],
            allowsMultipleSelection: Bool
        ) {
            self.presenter = presenter
            guard isPresented.wrappedValue,
                  picker == nil,
                  !isFinishing,
                  presenter.viewIfLoaded?.window != nil,
                  presenter.presentedViewController == nil else { return }

            let documentPicker = UIDocumentPickerViewController(
                forOpeningContentTypes: contentTypes,
                asCopy: false
            )
            documentPicker.delegate = self
            documentPicker.allowsMultipleSelection = allowsMultipleSelection
            documentPicker.shouldShowFileExtensions = true
            picker = documentPicker
            presenter.present(documentPicker, animated: true)
        }

        func dismissPickerIfNeeded() {
            guard let picker else { return }
            self.picker = nil
            picker.dismiss(animated: true)
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            finish {
                self.onCompletion(.success(urls))
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finish {
                self.onCancellation()
            }
        }

        private func finish(_ action: @escaping () -> Void) {
            guard !isFinishing else { return }
            isFinishing = true
            let activePicker = picker
            picker = nil

            let complete = { [weak self] in
                guard let self else { return }
                self.isPresented.wrappedValue = false
                action()
                self.isFinishing = false
            }

            if let activePicker {
                activePicker.dismiss(animated: true, completion: complete)
            } else {
                complete()
            }
        }
    }
}

extension View {
    func inrpfDocumentPicker(
        isPresented: Binding<Bool>,
        contentTypes: [UTType],
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[URL], Error>) -> Void,
        onCancellation: @escaping () -> Void = {}
    ) -> some View {
        background(
            INRPFDocumentPicker(
                isPresented: isPresented,
                contentTypes: contentTypes,
                allowsMultipleSelection: allowsMultipleSelection,
                onCompletion: onCompletion,
                onCancellation: onCancellation
            )
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }
}
