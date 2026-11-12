import Foundation

enum INRPFLocalUtilityCore {
    static func safePackageName(_ input: String, existingNames: [String]) -> String {
        let folded = input.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let ascii = folded.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            if (48...57).contains(value) || (65...90).contains(value) ||
                (97...122).contains(value) || value == 45 || value == 95 {
                return Character(scalar)
            }
            return "_"
        }
        var base = String(ascii).replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        if base.isEmpty { base = "dlc_pack" }
        base = String(base.prefix(48))
        let existing = Set(existingNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if !existing.contains(base.lowercased()) { return base }
        var suffix = 2
        while existing.contains("\(base)_\(suffix)".lowercased()) { suffix += 1 }
        return "\(base)_\(suffix)"
    }

    static func decodeHex(_ text: String) throws -> Data {
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty, tokens.count <= 512 * 1024 else {
            throw NSError(domain: "INRPF.Hex", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "أدخل بايتات Hex صحيحة ضمن حد 512KB."])
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(tokens.count)
        for token in tokens {
            guard token.count == 2, let byte = UInt8(token, radix: 16) else {
                throw NSError(domain: "INRPF.Hex", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "صيغة غير صحيحة عند القيمة: \(token). استخدم بايتين Hex مثل FF أو 0A."])
            }
            bytes.append(byte)
        }
        return Data(bytes)
    }

    static func structuralScore(_ report: ModAnalysisReport) -> Int {
        var score = 0
        if !report.dlcFiles.isEmpty { score += 20 }
        if !report.yftFiles.isEmpty { score += 15 }
        if !report.ytdFiles.isEmpty { score += 15 }
        if report.vehicleMetaFiles.contains(where: { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "vehicles.meta" }) { score += 15 }
        if report.vehicleMetaFiles.contains(where: { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "handling.meta" }) { score += 10 }
        if report.vehicleMetaFiles.contains(where: { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "carvariations.meta" }) { score += 10 }
        if !report.manifestFiles.isEmpty { score += 10 }
        if report.duplicatePackNames.isEmpty { score += 5 }
        return min(100, score)
    }

    static func dependencyReport(at root: URL) throws -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "INRPF.Dependency", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "تعذر قراءة مجلد المورد."])
        }
        var manifests: [URL] = []
        for case let file as URL in enumerator where ["fxmanifest.lua", "__resource.lua"].contains(file.lastPathComponent.lowercased()) {
            manifests.append(file)
        }
        guard !manifests.isEmpty else {
            return "لم يتم العثور على fxmanifest.lua أو __resource.lua. لا يمكن استنتاج اعتماديات FiveM من المجلد وحده."
        }
        var dependencies = Set<String>()
        var localReferences = Set<String>()
        for manifest in manifests {
            let values = try manifest.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 2 * 1024 * 1024 else { continue }
            let text = try String(contentsOf: manifest, encoding: .utf8)
            dependencies.formUnion(captures(#"dependency\s*\(?\s*['"]([^'"]+)['"]"#, in: text))
            for block in captures(#"dependencies\s*\{([^}]*)\}"#, in: text) {
                dependencies.formUnion(captures(#"['"]([^'"]+)['"]"#, in: block))
            }
            for block in captures(#"(?:files|client_scripts|server_scripts|shared_scripts)\s*\{([^}]*)\}"#, in: text) {
                localReferences.formUnion(captures(#"['"]([^'"]+)['"]"#, in: block))
            }
            localReferences.formUnion(captures(#"(?:client_script|server_script|shared_script|ui_page)\s+['"]([^'"]+)['"]"#, in: text))
        }
        var missing: [String] = []
        for path in localReferences.sorted() {
            if path.hasPrefix("@") || path.contains("*") || path.hasPrefix("http") { continue }
            let candidate = root.appendingPathComponent(path).standardizedFileURL
            let basePath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
            guard candidate.path.hasPrefix(basePath) else {
                missing.append("\(path) (مسار خارج المورد)")
                continue
            }
            if !fm.fileExists(atPath: candidate.path) { missing.append(path) }
        }
        return [
            "DEPENDENCY CHECK",
            "ملفات manifest: \(manifests.count)",
            "اعتماديات خارجية معلنة: \(dependencies.count)",
            dependencies.sorted().map { "dependency: \($0)" }.joined(separator: "\n"),
            "مراجع ملفات محلية: \(localReferences.count)",
            "مراجع غير موجودة أو خارج المورد: \(missing.count)",
            missing.isEmpty ? "لم يتم العثور على مراجع مفقودة ضمن الأنماط المدعومة." : missing.joined(separator: "\n")
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return source.substring(with: match.range(at: 1))
        }
    }
}
