import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum FileImportService {
    enum ImportFailure: LocalizedError {
        case missingSource
        case unsupportedItem
        case accessDenied
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingSource: return "الملف أو المجلد المختار غير موجود أو لم يعد متاحاً."
            case .unsupportedItem: return "العنصر المختار ليس ملفاً أو مجلداً عادياً."
            case .accessDenied: return "رفض iOS منح التطبيق صلاحية قراءة الملف. أعد اختيار الملف من تطبيق «الملفات»."
            case .copyFailed(let detail): return "فشل نسخ العنصر إلى مساحة التطبيق: \(detail)"
            }
        }
    }

    static func importItem(from source: URL, category: String = "Imports",
                           securityScopeAlreadyStarted: Bool = false) throws -> URL {
        let fm = FileManager.default
        let access = securityScopeAlreadyStarted ? false : source.startAccessingSecurityScopedResource()
        defer {
            if access { source.stopAccessingSecurityScopedResource() }
        }
        let sourcePath = source.standardizedFileURL.path
        let sandboxPath = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.path
        let isInsideAppSandbox = sourcePath == sandboxPath || sourcePath.hasPrefix(sandboxPath + "/")
        guard securityScopeAlreadyStarted || access || isInsideAppSandbox else {
            throw ImportFailure.accessDenied
        }

        let documents = try fm.url(for: .documentDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true)
        let appRoot = documents.appendingPathComponent("GTA Converter", isDirectory: true)
        let destinationParent = appRoot.appendingPathComponent(category, isDirectory: true)
        try fm.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        let destinationRoot = destinationParent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        do {
            var coordinatedURL: URL?
            var coordinationError: NSError?
            var operationError: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
                do {
                    var sourceIsDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: readableURL.path, isDirectory: &sourceIsDirectory) else {
                        throw ImportFailure.missingSource
                    }
                    if sourceIsDirectory.boolValue {
                        try copyDirectory(from: readableURL, to: destinationRoot)
                        coordinatedURL = destinationRoot
                    } else {
                        let destination = destinationRoot.appendingPathComponent(source.lastPathComponent)
                        try fm.copyItem(at: readableURL, to: destination)
                        coordinatedURL = destination
                    }
                } catch {
                    operationError = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let operationError { throw operationError }
            guard let coordinatedURL else { throw ImportFailure.missingSource }
            return coordinatedURL
        } catch {
            try? fm.removeItem(at: destinationRoot)
            throw ImportFailure.copyFailed(error.localizedDescription)
        }
    }

    private static func copyDirectory(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: source,
                                             includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                             options: []) else {
            throw ImportFailure.missingSource
        }
        var itemCount = 0
        for case let item as URL in enumerator {
            itemCount += 1
            guard itemCount <= 100_000 else {
                throw ImportFailure.copyFailed("المجلد يحتوي عدداً كبيراً جداً من العناصر.")
            }
            let relative = String(item.path.dropFirst(source.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let normalized = relative.replacingOccurrences(of: "\\", with: "/")
            let parts = normalized.split(separator: "/", omittingEmptySubsequences: true)
            guard !parts.isEmpty, !parts.contains(".."), !parts.contains("."),
                  !normalized.hasPrefix("/") else {
                throw ImportFailure.unsupportedItem
            }
            let target = destination.appendingPathComponent(parts.map(String.init).joined(separator: "/"))
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                continue
            }
            if values.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: item, to: target)
            }
        }
    }
}


/// Presents Apple's document picker in import-copy mode.
/// The selected item is materialized as a temporary copy before our app reads it.
struct INRPFDocumentPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let contentTypes: [UTType]
    let onCompletion: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented,
              host.presentedViewController == nil,
              !context.coordinator.isPresenting else { return }

        context.coordinator.isPresenting = true
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        host.present(picker, animated: true)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: INRPFDocumentPickerPresenter
        var isPresenting = false

        init(parent: INRPFDocumentPickerPresenter) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            isPresenting = false
            parent.isPresented = false
            parent.onCompletion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresenting = false
            parent.isPresented = false
        }
    }
}
