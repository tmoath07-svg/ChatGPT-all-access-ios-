import Foundation

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
        // Use coordinated reads for provider-backed URLs; the picker is opened in place
        // so folder providers do not need to stage a second temporary copy first.

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
            // Compare standardized path components instead of slicing path strings.
            // NSFileCoordinator may return a readable URL whose textual path differs
            // slightly from the selected URL (for example, trailing separators).
            let sourceComponents = source.standardizedFileURL.pathComponents
            let itemComponents = item.standardizedFileURL.pathComponents
            guard itemComponents.count > sourceComponents.count,
                  Array(itemComponents.prefix(sourceComponents.count)) == sourceComponents else {
                throw ImportFailure.unsupportedItem
            }
            let relativeComponents = Array(itemComponents.dropFirst(sourceComponents.count))
            guard !relativeComponents.isEmpty,
                  !relativeComponents.contains(".."),
                  !relativeComponents.contains(".") else {
                throw ImportFailure.unsupportedItem
            }
            let normalized = relativeComponents.joined(separator: "/")
            let target = destination.appendingPathComponent(normalized, isDirectory: false)
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
