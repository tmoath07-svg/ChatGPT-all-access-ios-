import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum INRPFOrbxAutoInstallPlanner {
    enum PlanError: LocalizedError {
        case missingAddonFolder
        case noPackages
        case invalidPackageName(String)
        case malformedXML(String)
        case missingPathsElement

        var errorDescription: String? {
            switch self {
            case .missingAddonFolder: return "مجلد data/orbx/gta/rpf/dlc_addon غير موجود."
            case .noPackages: return "لم يتم العثور على مجلدات DLC صالحة داخل dlc_addon."
            case .invalidPackageName(let name): return "اسم حزمة غير صالح: \(name)"
            case .malformedXML(let detail): return "ملف dlclist.xml غير صالح: \(detail)"
            case .missingPathsElement: return "ملف dlclist.xml لا يحتوي على عنصر Paths صالح."
            }
        }
    }

    static let remoteRoot = "/data/orbx/gta/rpf"
    static let remoteAddon = remoteRoot + "/dlc_addon"
    static let remoteDLClistDirectory = "/data/orbx/gta"

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
        return try validatePackageNames(names)
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
