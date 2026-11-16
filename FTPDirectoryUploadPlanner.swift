import Foundation

struct INRPFDirectoryUploadEntry: Equatable {
    let url: URL
    let relativePath: String
    let isDirectory: Bool
}

enum INRPFDirectoryUploadPlanner {
    static func plan(for root: URL) throws -> [INRPFDirectoryUploadEntry] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NSError(domain: "INRPF.FTPUpload", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "المجلد المحلي غير موجود أو ليس مجلداً."])
        }

        let standardizedRoot = root.standardizedFileURL
        let prefix = standardizedRoot.path + "/"
        guard let enumerator = fileManager.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw NSError(domain: "INRPF.FTPUpload", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "تعذر قراءة محتويات المجلد المحلي."])
        }

        var entries: [INRPFDirectoryUploadEntry] = []
        var visited = 0
        for case let item as URL in enumerator {
            visited += 1
            guard visited <= 100_000 else {
                throw NSError(domain: "INRPF.FTPUpload", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "المجلد يحتوي عدداً كبيراً جداً من العناصر."])
            }

            let standardizedItem = item.standardizedFileURL
            guard standardizedItem.path.hasPrefix(prefix) else {
                throw NSError(domain: "INRPF.FTPUpload", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "تم رفض مسار عنصر خارج المجلد المحدد."])
            }

            let relative = String(standardizedItem.path.dropFirst(prefix.count))
            let components = relative.split(separator: "/").map(String.init)
            guard !components.isEmpty,
                  !components.contains(".."),
                  !components.contains("."),
                  components.allSatisfy({ !$0.isEmpty && !$0.contains("\\") }) else {
                throw NSError(domain: "INRPF.FTPUpload", code: 5,
                              userInfo: [NSLocalizedDescriptionKey: "يحتوي المجلد على مسار غير صالح."])
            }

            let values = try standardizedItem.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            entries.append(INRPFDirectoryUploadEntry(
                url: standardizedItem,
                relativePath: components.joined(separator: "/"),
                isDirectory: values.isDirectory == true
            ))
        }

        return entries.sorted {
            let left = $0.relativePath.split(separator: "/").count
            let right = $1.relativePath.split(separator: "/").count
            if left != right { return left < right }
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.relativePath < $1.relativePath
        }
    }
}
