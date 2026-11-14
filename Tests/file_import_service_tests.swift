import Foundation

@main
struct FileImportServiceTests {
    static func main() throws {
        let fm = FileManager.default
        let fixtureRoot = fm.temporaryDirectory.appendingPathComponent("INRPF-Import-Fixtures-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: fixtureRoot) }

        let category = "INRPFImportServiceTests"
        let importedCategory = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("GTA Converter", isDirectory: true)
            .appendingPathComponent(category, isDirectory: true)
        defer { try? fm.removeItem(at: importedCategory) }

        let expectedBytes = Data([0x49, 0x4E, 0x52, 0x50, 0x46, 0x2D, 0x54, 0x45, 0x53, 0x54])
        let sourceFile = fixtureRoot.appendingPathComponent("sample.zip")
        try expectedBytes.write(to: sourceFile)

        let importedFile = try FileImportService.importItem(from: sourceFile, category: category)
        let importedBytes = try Data(contentsOf: importedFile)
        precondition(importedBytes == expectedBytes, "Imported file bytes differ from source.")
        let originalBytes = try Data(contentsOf: sourceFile)
        precondition(originalBytes == expectedBytes, "Original source file was modified.")

        let sourceFolder = fixtureRoot.appendingPathComponent("sample-mod", isDirectory: true)
        let nestedFolder = sourceFolder.appendingPathComponent("vehicles/stream", isDirectory: true)
        let emptyFolder = sourceFolder.appendingPathComponent("empty-folder", isDirectory: true)
        try fm.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        let nestedFile = nestedFolder.appendingPathComponent("vehicle.yft")
        let nestedBytes = Data([0x59, 0x46, 0x54, 0x2D, 0x44, 0x41, 0x54, 0x41])
        try nestedBytes.write(to: nestedFile)

        let link = nestedFolder.appendingPathComponent("ignored-link")
        try fm.createSymbolicLink(at: link, withDestinationURL: nestedFile)

        let importedFolder = try FileImportService.importItem(from: sourceFolder, category: category)
        // FileImportService copies the selected folder's contents directly into its
        // generated destination directory; it does not add the source folder name.
        let copiedNestedFile = importedFolder.appendingPathComponent("vehicles/stream/vehicle.yft")
        guard fm.fileExists(atPath: copiedNestedFile.path) else {
            let enumerator = fm.enumerator(at: importedFolder, includingPropertiesForKeys: nil)
            let actualPaths = (enumerator?.allObjects as? [URL] ?? []).map {
                String($0.path.dropFirst(importedFolder.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }.sorted()
            fatalError("Nested file missing. Expected: vehicles/stream/vehicle.yft. Actual copied paths: \\(actualPaths)")
        }
        let copiedNestedBytes = try Data(contentsOf: copiedNestedFile)
        precondition(copiedNestedBytes == nestedBytes, "Nested folder content was not copied correctly.")

        var emptyIsDirectory: ObjCBool = false
        let copiedEmptyFolder = importedFolder.appendingPathComponent("empty-folder")
        precondition(fm.fileExists(atPath: copiedEmptyFolder.path, isDirectory: &emptyIsDirectory) && emptyIsDirectory.boolValue,
                     "Empty directories must be preserved.")

        let copiedLink = importedFolder.appendingPathComponent("vehicles/stream/ignored-link")
        precondition(!fm.fileExists(atPath: copiedLink.path), "Symbolic links must not be copied.")

        print("PASS: file bytes, original preservation, nested folder, empty folder, and symlink handling.")
    }
}
