import Foundation
import CryptoKit

struct INRPFComparedFile: Equatable {
    enum Change: String { case added, removed, changed, unchanged }
    let path: String
    let change: Change
    let leftBytes: Int64?
    let rightBytes: Int64?
}

enum INRPFFileComparison {
    static func compare(left: URL, right: URL) throws -> [INRPFComparedFile] {
        let lhs = try inventory(left)
        let rhs = try inventory(right)
        let paths = Set(lhs.keys).union(rhs.keys).sorted()
        return paths.map { path in
            let a = lhs[path], b = rhs[path]
            let change: INRPFComparedFile.Change
            if a == nil { change = .added }
            else if b == nil { change = .removed }
            else if a!.hash != b!.hash { change = .changed }
            else { change = .unchanged }
            return INRPFComparedFile(path: path, change: change,
                                     leftBytes: a?.bytes, rightBytes: b?.bytes)
        }
    }

    private static func inventory(_ root: URL) throws -> [String: (bytes: Int64, hash: String)] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NSError(domain: "INRPF.Compare", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "يجب اختيار مجلد صالح للمقارنة."])
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "INRPF.Compare", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "تعذر قراءة ملفات المجلد."])
        }
        var result: [String: (bytes: Int64, hash: String)] = [:]
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true || values.isRegularFile != true { continue }
            let relative = String(file.path.dropFirst(root.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty,
                  !relative.split(separator: "/").contains("..") else { continue }
            let data = try Data(contentsOf: file, options: [.mappedIfSafe])
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            result[relative] = (Int64(values.fileSize ?? data.count), hash)
        }
        return result
    }
}

struct INRPFHandlingField: Equatable {
    let name: String
    let value: String
}

enum INRPFHandlingParser {
    static func parse(data: Data) throws -> [INRPFHandlingField] {
        let delegate = HandlingXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.fields.isEmpty == false else {
            throw NSError(domain: "INRPF.Handling", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: parser.parserError?.localizedDescription ?? "لم يتم العثور على حقول Handling صالحة."])
        }
        return delegate.fields.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private final class HandlingXMLDelegate: NSObject, XMLParserDelegate {
    private struct ElementFrame {
        let name: String
        let valueAttribute: String?
        var text: String
        var hasChild: Bool
    }

    var fields: [INRPFHandlingField] = []
    private var stack: [ElementFrame] = []
    private let ignored: Set<String> = ["Item", "HandlingData", "HandlingDataMgr", "CHandlingData"]

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if !stack.isEmpty {
            stack[stack.count - 1].hasChild = true
        }
        stack.append(ElementFrame(
            name: elementName,
            valueAttribute: attributeDict["value"],
            text: "",
            hasChild: false
        ))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard let frame = stack.popLast() else { return }
        guard !frame.hasChild, !ignored.contains(frame.name) else { return }

        let textValue = frame.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (frame.valueAttribute ?? textValue).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        fields.append(INRPFHandlingField(name: frame.name, value: value))
    }
}
