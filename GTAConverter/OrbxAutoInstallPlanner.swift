import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum INRPFOrbxAutoInstallPlanner {
    enum PlanError: LocalizedError {
        case missingAddonFolder
        case noPackages
        case missingDlcRPF(String)
        case ambiguousDlcRPF(Int)
        case invalidDLClistEntry
        case invalidPackageName(String)
        case malformedXML(String)
        case missingPathsElement

        var errorDescription: String? {
            switch self {
            case .missingAddonFolder: return "مجلد Data/orbx/gta/rpf/dlc_addon غير موجود."
            case .noPackages: return "لم يتم العثور على مجلدات DLC صالحة داخل dlc_addon."
            case .missingDlcRPF(let name): return "الحزمة \(name) لا تحتوي على ملف dlc.rpf مباشرة داخل مجلدها."
            case .ambiguousDlcRPF(let count): return "تم العثور على \(count) ملفات dlc.rpf؛ يلزم ملف واحد فقط مع مدخل DLCLIST واحد."
            case .invalidDLClistEntry: return "تعذر استخراج اسم الحزمة من dlclist-entry. يجب أن يحتوي المسار على dlc_addon/NAME/."
            case .invalidPackageName(let name): return "اسم حزمة غير صالح: \(name)"
            case .malformedXML(let detail): return "ملف dlclist.xml غير صالح: \(detail)"
            case .missingPathsElement: return "ملف dlclist.xml لا يحتوي على عنصر Paths صالح."
            }
        }
    }

    static let remoteRoot = "/data/orbx/gta/rpf"
    static let remoteAddon = remoteRoot + "/dlc_addon"
    static let remoteDLClistDirectory = "/data/orbx/gta"

    /// Resolve the generated add-on folder without assuming filesystem case.
    /// New packages use canonical "Data"; legacy "data" packages remain readable.
    static func addonFolder(in packageURL: URL) throws -> URL {
        let children = try FileManager.default.contentsOfDirectory(
            at: packageURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )
        let matches = children.filter { child in
            guard child.lastPathComponent.caseInsensitiveCompare("Data") == .orderedSame else {
                return false
            }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        guard matches.count == 1, let dataRoot = matches.first else {
            throw PlanError.missingAddonFolder
        }
        let addon = dataRoot
            .appendingPathComponent("orbx", isDirectory: true)
            .appendingPathComponent("gta", isDirectory: true)
            .appendingPathComponent("rpf", isDirectory: true)
            .appendingPathComponent("dlc_addon", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: addon.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw PlanError.missingAddonFolder }
        return addon
    }

    /// Removes exactly one redundant same-name wrapper folder, without flattening valid DLC subfolders.
    static func packageContentRoot(for packageFolder: URL) throws -> URL {
        let children = try FileManager.default.contentsOfDirectory(
            at: packageFolder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        guard children.count == 1, let only = children.first,
              only.lastPathComponent.caseInsensitiveCompare(packageFolder.lastPathComponent) == .orderedSame else {
            return packageFolder
        }
        let values = try only.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { return packageFolder }
        return only
    }

    /// Orbx expects one RPF archive directly inside each addon package folder.
    static func validateDlcRPF(in packageFolder: URL) throws {
        let root = try packageContentRoot(for: packageFolder)
        let archive = root.appendingPathComponent("dlc.rpf", isDirectory: false)
        let values = try? archive.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isDirectory != true, values?.isSymbolicLink != true else {
            throw PlanError.missingDlcRPF(packageFolder.lastPathComponent)
        }
    }

    /// Converts an imported prepared-DLC bundle into the exact Orbx layout.
    /// The package name is taken from dlclist-entry, and only dlc.rpf is retained.
    /// Returns nil for ordinary imports that do not contain a DLCLIST entry.
    static func normalizePreparedDLC(at importedRoot: URL) throws -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: importedRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { throw PlanError.invalidDLClistEntry }

        var archives: [URL] = []
        var entryFiles: [URL] = []
        while let file = enumerator.nextObject() as? URL {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            let filename = file.lastPathComponent.lowercased()
            if filename == "dlc.rpf" { archives.append(file) }
            if filename == "dlclist-entry" || filename == "dlclist-entry.txt" || filename == "dlclist.xml" {
                entryFiles.append(file)
            }
        }

        guard !entryFiles.isEmpty else { return nil }
        // Ambiguous prepared imports are ignored for Orbx normalization.
        // Keep the extracted staging files untouched; the selected source archive is never modified.
        guard archives.count == 1 else { return nil }

        let regex = try NSRegularExpression(pattern: #"(?i)dlc_addon/([A-Za-z0-9_-]{1,64})/"#)
        var names = Set<String>()
        for entry in entryFiles {
            let content = try String(contentsOf: entry, encoding: .utf8)
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            for match in regex.matches(in: content, range: range) {
                if let nameRange = Range(match.range(at: 1), in: content) {
                    names.insert(String(content[nameRange]))
                }
            }
        }
        guard names.count == 1, let name = names.first, isValidPackageName(name) else {
            throw PlanError.invalidDLClistEntry
        }

        let temporary = importedRoot.deletingLastPathComponent()
            .appendingPathComponent(".inrpf-orbx-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temporary) }
        let gta = temporary.appendingPathComponent("data/orbx/gta", isDirectory: true)
        let package = gta.appendingPathComponent("rpf/dlc_addon/\(name)", isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        try fm.copyItem(at: archives[0], to: package.appendingPathComponent("dlc.rpf"))

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <SMandatoryPacksData>
          <Paths>
            <Item>/data/orbx/gta/rpf/dlc_addon/\(name)/</Item>
          </Paths>
        </SMandatoryPacksData>
        """
        try xml.write(to: gta.appendingPathComponent("dlclist.xml"), atomically: true, encoding: .utf8)

        // Replace only the app-managed staging copy; the user's source archive remains untouched.
        for child in try fm.contentsOfDirectory(at: importedRoot, includingPropertiesForKeys: nil) {
            try fm.removeItem(at: child)
        }
        try fm.moveItem(at: temporary.appendingPathComponent("data", isDirectory: true),
                        to: importedRoot.appendingPathComponent("data", isDirectory: true))
        return name
    }

    static func isValidPackageName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64 else { return false }
        return name.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    static func validatePackageNames(_ names: [String]) throws -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            guard isValidPackageName(name) else { throw PlanError.invalidPackageName(name) }
            if seen.insert(name.lowercased()).inserted { result.append(name) }
        }
        guard !result.isEmpty else { throw PlanError.noPackages }
        return result.sorted()
    }

    static func discoverPackageNames(in addonFolder: URL) throws -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: addonFolder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw PlanError.missingAddonFolder }

        let children = try FileManager.default.contentsOfDirectory(
            at: addonFolder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let names = children.compactMap { child -> String? in
            guard isValidPackageName(child.lastPathComponent),
                  let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return child.lastPathComponent
        }
        let validated = try validatePackageNames(names)
        for name in validated {
            try validateDlcRPF(in: addonFolder.appendingPathComponent(name, isDirectory: true))
        }
        return validated
    }

    static func mergedDLClist(existing: String?, packageNames: [String]) throws -> String {
        let names = try validatePackageNames(packageNames)
        let source = existing ?? """
        <?xml version="1.0" encoding="UTF-8"?>
        <SMandatoryPacksData>
          <Paths>
          </Paths>
        </SMandatoryPacksData>
        """

        let parsed = try parse(source)
        guard parsed.hasPaths else { throw PlanError.missingPathsElement }
        var existingItems = Set(parsed.items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let additions = names.compactMap { name -> String? in
            let path = "\(remoteAddon)/\(name)/"
            return existingItems.insert(path.lowercased()).inserted ? "<Item>\(path)</Item>" : nil
        }

        guard !additions.isEmpty else { return source }
        guard let close = source.range(of: "</Paths>", options: .caseInsensitive) else {
            throw PlanError.missingPathsElement
        }
        let insertion = additions.map { "    \($0)" }.joined(separator: "\n") + "\n  "
        var output = source
        output.insert(contentsOf: insertion, at: close.lowerBound)
        _ = try parse(output)
        return output
    }

    private static func parse(_ xml: String) throws -> (hasPaths: Bool, items: [String]) {
        guard let data = xml.data(using: .utf8) else {
            throw PlanError.malformedXML("تعذر قراءة النص بترميز UTF-8.")
        }
        let delegate = XMLStructureReader()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw PlanError.malformedXML(parser.parserError?.localizedDescription ?? "XML parsing failed")
        }
        return (delegate.hasPaths, delegate.items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
}

private final class XMLStructureReader: NSObject, XMLParserDelegate {
    private(set) var hasPaths = false
    private(set) var items: [String] = []
    private var insidePaths = false
    private var insideItem = false
    private var currentItem = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName.caseInsensitiveCompare("Paths") == .orderedSame {
            insidePaths = true
            hasPaths = true
        } else if insidePaths && elementName.caseInsensitiveCompare("Item") == .orderedSame {
            insideItem = true
            currentItem = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem { currentItem += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if insideItem && elementName.caseInsensitiveCompare("Item") == .orderedSame {
            items.append(currentItem)
            insideItem = false
            currentItem = ""
        } else if elementName.caseInsensitiveCompare("Paths") == .orderedSame {
            insidePaths = false
        }
    }
}
