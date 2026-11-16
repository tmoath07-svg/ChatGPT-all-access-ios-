import Foundation

@main
struct FeatureAnalysisTests {
    static func main() throws {
        try testHandlingParser()
        try testFolderComparison()
        print("FEATURE ANALYSIS TESTS: PASS")
    }

    private static func testHandlingParser() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HandlingData>
          <Item type="CHandlingData">
            <handlingName>adder</handlingName>
            <fMass value="1500.000000" />
            <fInitialDriveForce value="0.320000" />
          </Item>
          <Item type="CHandlingData">
            <handlingName>buffalo</handlingName>
            <fMass value="1600.000000" />
          </Item>
        </HandlingData>
        """
        let fields = try INRPFHandlingParser.parse(data: Data(xml.utf8))
        let masses = fields.filter { $0.name == "fMass" }.map(\.value).sorted()
        precondition(masses == ["1500.000000", "1600.000000"], "Handling value attributes or repeated vehicle entries were lost")
        precondition(fields.contains { $0.name == "handlingName" && $0.value == "adder" }, "Text-valued handlingName was not parsed")
        precondition(fields.contains { $0.name == "fInitialDriveForce" && $0.value == "0.320000" }, "Numeric value attribute was not parsed")
    }

    private static func testFolderComparison() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("inrpf-compare-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let left = root.appendingPathComponent("left", isDirectory: true)
        let right = root.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        try write("same", to: left.appendingPathComponent("same.txt"))
        try write("before", to: left.appendingPathComponent("changed.txt"))
        try write("remove", to: left.appendingPathComponent("removed.txt"))
        try write("same", to: right.appendingPathComponent("same.txt"))
        try write("after", to: right.appendingPathComponent("changed.txt"))
        try write("new", to: right.appendingPathComponent("added.txt"))
        try write("nested", to: left.appendingPathComponent("nested/keep.txt"))
        try write("nested", to: right.appendingPathComponent("nested/keep.txt"))

        let changes = try INRPFFileComparison.compare(left: left, right: right)
        precondition(changes.count == 5, "Comparison expected 5 paths, got \(changes.count): \(changes.map(\.path))")
        precondition(changes.filter { $0.change == .unchanged }.map(\.path) == ["nested/keep.txt", "same.txt"], "Unchanged file classification failed: \(changes.filter { $0.change == .unchanged }.map(\.path))")
        precondition(changes.filter { $0.change == .changed }.map(\.path) == ["changed.txt"], "Changed file classification failed")
        precondition(changes.filter { $0.change == .removed }.map(\.path) == ["removed.txt"], "Removed file classification failed")
        precondition(changes.filter { $0.change == .added }.map(\.path) == ["added.txt"], "Added file classification failed")
        precondition(changes.contains { $0.path == "nested/keep.txt" && $0.change == .unchanged }, "Nested file inventory failed")
    }

    private static func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: url)
    }
}
