import Foundation

struct ModAnalysisReport {
    let fileCount: Int
    let totalBytes: Int64
    let dlcFiles: [String]
    let packNames: [String]
    let readmeFiles: [String]
    let duplicatePackNames: [String]
    let yftFiles: [String]
    let ytdFiles: [String]
    let vehicleMetaFiles: [String]
    let manifestFiles: [String]
    let isFiveMVehicleResource: Bool
    let resourceRootRelative: String?
    let reportText: String
}

enum ModAnalyzer {
    /// Finds the nearest valid FiveM resource root, even when an archive adds wrapper folders.
    static func discoverFiveMResourceRoot(in importedRoot: URL) throws -> URL? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: importedRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        func hasManifest(_ directory: URL) -> Bool {
            fm.fileExists(atPath: directory.appendingPathComponent("fxmanifest.lua").path) ||
            fm.fileExists(atPath: directory.appendingPathComponent("__resource.lua").path)
        }

        // The selected folder itself may already be the resource root.
        if hasManifest(importedRoot) { return importedRoot.standardizedFileURL }

        var candidates: [(URL, Int)] = []
        guard let enumerator = fm.enumerator(at: importedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]) else { return nil }
        var visited = 0
        while let item = enumerator.nextObject() as? URL {
            visited += 1
            if visited > 20_000 {
                throw NSError(domain: "GTAConverter.ModAnalyzer", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "تجاوز البحث عن جذر FiveM حد 20,000 عنصر."])
            }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isDirectory == true else { continue }
            if hasManifest(item) {
                candidates.append((item.standardizedFileURL, item.pathComponents.count))
                enumerator.skipDescendants()
            }
        }
        return candidates.sorted { $0.1 < $1.1 }.first?.0
    }

    static func analyze(at importedRoot: URL) throws -> ModAnalysisReport {
        let fm = FileManager.default
        let discoveredRoot = try discoverFiveMResourceRoot(in: importedRoot)
        let root = discoveredRoot ?? importedRoot
        let resourceRootRelative: String? = {
            guard let discoveredRoot else { return nil }
            let base = importedRoot.standardizedFileURL.path
            let selected = discoveredRoot.standardizedFileURL.path
            if selected == base { return "." }
            let prefix = base.hasSuffix("/") ? base : base + "/"
            guard selected.hasPrefix(prefix) else { return nil }
            return String(selected.dropFirst(prefix.count))
        }()
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
        var yftFiles: [String] = []
        var ytdFiles: [String] = []
        var vehicleMetaFiles: [String] = []
        var manifestFiles: [String] = []
        let vehicleMetaNames: Set<String> = ["vehicles.meta", "handling.meta", "carcols.meta", "carvariations.meta", "vehiclelayouts.meta"]

        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard values.isDirectory != true else { continue }
            fileCount += 1
            totalBytes += Int64(values.fileSize ?? 0)
            let relative = String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let lower = url.lastPathComponent.lowercased()
            let ext = url.pathExtension.lowercased()

            if lower == "dlc.rpf" {
                dlcFiles.append(relative)
                let name = url.deletingLastPathComponent().lastPathComponent
                if name.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil { allNames.append(name) }
            }
            if lower == "readme.txt" || lower == "readme.md" || lower == "read me.txt" { readmes.append(relative) }
            if ext == "yft" { yftFiles.append(relative) }
            if ext == "ytd" { ytdFiles.append(relative) }
            if ext == "yft" || ext == "ytd" {
                let genericFolders: Set<String> = ["stream", "vehicles", "vehicle", "data", "common", "x64", "dlc", "dlcpacks", "addon", "addons", "models", "textures"]
                let components = relative.split(separator: "/").dropLast()
                if components.count > 1,
                   let candidate = components.reversed().first(where: { !genericFolders.contains($0.lowercased()) }),
                   candidate.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil {
                    allNames.append(String(candidate))
                }
            }
            if vehicleMetaNames.contains(lower) { vehicleMetaFiles.append(relative) }
            if lower == "fxmanifest.lua" || lower == "__resource.lua" { manifestFiles.append(relative) }
            if fileCount > 20_000 {
                throw NSError(domain: "GTAConverter.ModAnalyzer", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "المجلد يحتوي أكثر من 20,000 ملف."])
            }
        }

        let counts = Dictionary(grouping: allNames, by: { $0.lowercased() })
        let duplicates = counts.values.filter { $0.count > 1 }.compactMap { $0.first }.sorted()
        let names = Array(Set(allNames)).sorted()
        let hasVehiclesMeta = vehicleMetaFiles.contains { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "vehicles.meta" }
        let hasHandlingMeta = vehicleMetaFiles.contains { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "handling.meta" }
        let isFiveMVehicleResource = !yftFiles.isEmpty && hasVehiclesMeta && (!manifestFiles.isEmpty || hasHandlingMeta || !ytdFiles.isEmpty)
        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        var lines = [
            "GTA MOD ANALYSIS", "عدد الملفات: \(fileCount)", "الحجم بعد الفك: \(size)",
            "ملفات DLC.RPF: \(dlcFiles.count)", "أسماء DLC المكتشفة: \(names.count)",
            "ملفات Readme: \(readmes.count)", "ملفات موديل YFT: \(yftFiles.count)",
            "ملفات خامات YTD: \(ytdFiles.count)", "ملفات META للمركبات: \(vehicleMetaFiles.count)",
            "ملفات Manifest: \(manifestFiles.count)"
        ]
        if !names.isEmpty { lines.append("أسماء الحزم:\n" + names.joined(separator: "\n")) }
        if !dlcFiles.isEmpty { lines.append("مسارات DLC.RPF:\n" + dlcFiles.prefix(30).joined(separator: "\n")) }
        if !readmes.isEmpty { lines.append("ملفات التعليمات:\n" + readmes.prefix(15).joined(separator: "\n")) }
        if !duplicates.isEmpty { lines.append("أسماء مكررة في أكثر من مسار:\n" + duplicates.joined(separator: "\n")) }
        if !yftFiles.isEmpty { lines.append("مسارات YFT:\n" + yftFiles.prefix(20).joined(separator: "\n")) }
        if !ytdFiles.isEmpty { lines.append("مسارات YTD:\n" + ytdFiles.prefix(20).joined(separator: "\n")) }
        if !vehicleMetaFiles.isEmpty { lines.append("ملفات META:\n" + vehicleMetaFiles.sorted().joined(separator: "\n")) }
        if !manifestFiles.isEmpty { lines.append("ملفات FiveM Manifest:\n" + manifestFiles.sorted().joined(separator: "\n")) }
        if isFiveMVehicleResource {
            lines.append("النتيجة: تم التعرف على مورد سيارة FiveM يحتوي ملفات موديل وخامات وملفات تعريف. يحتاج تحويل بنية المورد وملفات META إلى حزمة DLC متوافقة مع PS4؛ فك الملفات وحده ليس تحويلاً.")
        } else if vehicleMetaFiles.isEmpty {
            lines.append("النتيجة: لم يتم التعرف على مود مركبة مدعوم. تم الاحتفاظ بجرد الملفات الفعلي بدلاً من إرجاع أرقام صفرية مضللة.")
        } else if dlcFiles.isEmpty {
            lines.append("النتيجة: لم يتم العثور على dlc.rpf أو بنية سيارة FiveM مكتملة.")
        } else {
            lines.append("النتيجة: تم العثور على ملفات DLC ويمكن تجهيز قائمة الحزم.")
        }

        return ModAnalysisReport(fileCount: fileCount, totalBytes: totalBytes, dlcFiles: dlcFiles.sorted(),
            packNames: names, readmeFiles: readmes.sorted(), duplicatePackNames: duplicates,
            yftFiles: yftFiles.sorted(), ytdFiles: ytdFiles.sorted(), vehicleMetaFiles: vehicleMetaFiles.sorted(),
            manifestFiles: manifestFiles.sorted(), isFiveMVehicleResource: isFiveMVehicleResource,
            resourceRootRelative: resourceRootRelative, reportText: lines.joined(separator: "\n"))
    }
}
