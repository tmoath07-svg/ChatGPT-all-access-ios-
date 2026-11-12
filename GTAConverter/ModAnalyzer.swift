import Foundation

struct ModAnalysisReport {
    let fileCount: Int
    let totalBytes: Int64
    let dlcFiles: [String]
    let packNames: [String]
    let readmeFiles: [String]
    let duplicatePackNames: [String]
    let reportText: String
}

enum ModAnalyzer {
    static func analyze(at root: URL) throws -> ModAnalysisReport {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(domain: "GTAConverter.ModAnalyzer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "تعذر فتح مجلد الملفات الناتجة."])
        }

        var fileCount = 0
        var totalBytes: Int64 = 0
        var dlcFiles: [String] = []
        var readmes: [String] = []
        var allNames: [String] = []

        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard values.isDirectory != true else { continue }
            fileCount += 1
            totalBytes += Int64(values.fileSize ?? 0)
            let relative = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let lower = url.lastPathComponent.lowercased()
            if lower == "dlc.rpf" {
                dlcFiles.append(relative)
                let name = url.deletingLastPathComponent().lastPathComponent
                if name.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil {
                    allNames.append(name)
                }
            }
            if lower == "readme.txt" || lower == "readme.md" || lower == "read me.txt" {
                readmes.append(relative)
            }
            if fileCount > 20_000 {
                throw NSError(domain: "GTAConverter.ModAnalyzer", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "المجلد يحتوي أكثر من 20,000 ملف."])
            }
        }

        let counts = Dictionary(grouping: allNames, by: { $0.lowercased() })
        let duplicates = counts.values.filter { $0.count > 1 }.compactMap { $0.first }.sorted()
        let names = Array(Set(allNames)).sorted()
        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        var lines = [
            "GTA MOD ANALYSIS",
            "عدد الملفات: \(fileCount)",
            "الحجم بعد الفك: \(size)",
            "ملفات DLC.RPF: \(dlcFiles.count)",
            "أسماء DLC المكتشفة: \(names.count)",
            "ملفات Readme: \(readmes.count)"
        ]
        if !names.isEmpty { lines.append("أسماء الحزم:\n" + names.joined(separator: "\n")) }
        if !dlcFiles.isEmpty { lines.append("مسارات DLC.RPF:\n" + dlcFiles.prefix(30).joined(separator: "\n")) }
        if !readmes.isEmpty { lines.append("ملفات التعليمات:\n" + readmes.prefix(15).joined(separator: "\n")) }
        if !duplicates.isEmpty { lines.append("أسماء مكررة في أكثر من مسار:\n" + duplicates.joined(separator: "\n")) }
        if dlcFiles.isEmpty {
            lines.append("النتيجة: لم يتم العثور على dlc.rpf. المجلد قد لا يكون مود سيارة Add-On.")
        } else {
            lines.append("النتيجة: تم العثور على ملفات DLC ويمكن تجهيز قائمة الحزم.")
        }
        return ModAnalysisReport(
            fileCount: fileCount,
            totalBytes: totalBytes,
            dlcFiles: dlcFiles.sorted(),
            packNames: names,
            readmeFiles: readmes.sorted(),
            duplicatePackNames: duplicates,
            reportText: lines.joined(separator: "\n")
        )
    }
}
