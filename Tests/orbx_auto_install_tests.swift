import Foundation

@main
struct OrbxAutoInstallTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("inrpf-auto-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let addon = root.appendingPathComponent("data/orbx/gta/rpf/dlc_addon", isDirectory: true)
        let alpha = addon.appendingPathComponent("alpha_pack", isDirectory: true)
        let beta = addon.appendingPathComponent("car_2026", isDirectory: true)
        try FileManager.default.createDirectory(at: alpha.appendingPathComponent("stream", isDirectory: true),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
        try Data("fixture-model".utf8).write(to: alpha.appendingPathComponent("stream/car.oft"))
        try Data("fixture-meta".utf8).write(to: beta.appendingPathComponent("vehicles.meta"))

        let names = try INRPFOrbxAutoInstallPlanner.discoverPackageNames(in: addon)
        precondition(names == ["alpha_pack", "car_2026"], "DLC folder discovery did not return expected names")

        let rpfRoot = root.appendingPathComponent("data/orbx/gta/rpf", isDirectory: true)
        try FileManager.default.createDirectory(at: rpfRoot, withIntermediateDirectories: true)
        let dlclistFile = rpfRoot.appendingPathComponent("dlclist.xml")
        let original = """
        <?xml version="1.0" encoding="UTF-8"?>
        <SMandatoryPacksData>
          <Paths>
            <Item>/data/orbx/gta/rpf/dlc_addon/old_pack/</Item>
          </Paths>
        </SMandatoryPacksData>
        """
        try original.write(to: dlclistFile, atomically: true, encoding: .utf8)
        let onDiskOriginal = try String(contentsOf: dlclistFile, encoding: .utf8)
        let merged = try INRPFOrbxAutoInstallPlanner.mergedDLClist(existing: onDiskOriginal, packageNames: names)
        try merged.write(to: dlclistFile, atomically: true, encoding: .utf8)
        let onDiskMerged = try String(contentsOf: dlclistFile, encoding: .utf8)
        precondition(onDiskMerged == merged, "dlclist.xml fixture was not written correctly")
        precondition(merged.contains("/data/orbx/gta/rpf/dlc_addon/old_pack/"), "Existing XML entries were not preserved")
        precondition(merged.contains("/data/orbx/gta/rpf/dlc_addon/alpha_pack/"), "First package path missing")
        precondition(merged.contains("/data/orbx/gta/rpf/dlc_addon/car_2026/"), "Second package path missing")

        let repeated = try INRPFOrbxAutoInstallPlanner.mergedDLClist(existing: merged, packageNames: names)
        precondition(repeated == merged, "Merge is not idempotent; duplicate paths may be added")

        let fresh = try INRPFOrbxAutoInstallPlanner.mergedDLClist(existing: nil, packageNames: names)
        precondition(fresh.contains("<SMandatoryPacksData>") && fresh.contains("</Paths>"),
                     "Fresh dlclist.xml skeleton is invalid")

        do {
            _ = try INRPFOrbxAutoInstallPlanner.mergedDLClist(existing: "<broken><Paths></broken>", packageNames: names)
            fatalError("Malformed XML was incorrectly accepted")
        } catch is INRPFOrbxAutoInstallPlanner.PlanError {
            // Expected: malformed XML is rejected before uploads begin.
        }

        do {
            _ = try INRPFOrbxAutoInstallPlanner.validatePackageNames(["../escape"])
            fatalError("Unsafe package name was incorrectly accepted")
        } catch is INRPFOrbxAutoInstallPlanner.PlanError {
            // Expected: unsafe path components are rejected.
        }

        print("ORBX AUTO INSTALL TESTS: PASS")
        print("Fixture folder: data/orbx/gta/rpf/dlc_addon/")
        print("Fixture file: data/orbx/gta/rpf/dlclist.xml")
        print("Packages: \(names.joined(separator: ", "))")
        print("XML: existing entries preserved, paths merged, duplicate-safe, malformed XML rejected.")
    }
}
