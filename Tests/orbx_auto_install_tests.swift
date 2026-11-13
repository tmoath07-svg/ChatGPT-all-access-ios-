import Foundation

@main
struct OrbxAutoInstallTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("inrpf-auto-fixture-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let packageRoot = root.appendingPathComponent("PS4-Orbx-Fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let addon = packageRoot.appendingPathComponent("Data/orbx/gta/rpf/dlc_addon", isDirectory: true)
        try FileManager.default.createDirectory(at: addon, withIntermediateDirectories: true)
        let resolvedAddon = try INRPFOrbxAutoInstallPlanner.addonFolder(in: packageRoot)
        precondition(resolvedAddon.path == addon.path, "Canonical Data folder resolution failed")
        let alpha = addon.appendingPathComponent("alpha_pack", isDirectory: true)
        let beta = addon.appendingPathComponent("car_2026", isDirectory: true)
        let optima = addon.appendingPathComponent("optima", isDirectory: true)
        let rbtitt = addon.appendingPathComponent("Rbtitt", isDirectory: true)
        let wrappedAlpha = alpha.appendingPathComponent("alpha_pack", isDirectory: true)
        try FileManager.default.createDirectory(at: wrappedAlpha.appendingPathComponent("stream", isDirectory: true),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: optima, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rbtitt, withIntermediateDirectories: true)
        try Data("fixture-model".utf8).write(to: wrappedAlpha.appendingPathComponent("stream/car.oft"))
        try Data("fixture-rpf-alpha".utf8).write(to: wrappedAlpha.appendingPathComponent("dlc.rpf"))
        let normalizedAlpha = try INRPFOrbxAutoInstallPlanner.packageContentRoot(for: alpha)
        precondition(normalizedAlpha.lastPathComponent == "alpha_pack", "Same-name wrapper folder was not removed")
        precondition(FileManager.default.fileExists(atPath: normalizedAlpha.appendingPathComponent("stream/car.oft").path),
                     "Normalized package root does not expose DLC files directly")
        let normalizedBeta = try INRPFOrbxAutoInstallPlanner.packageContentRoot(for: beta)
        precondition(normalizedBeta == beta, "A valid package folder was incorrectly flattened")
        try Data("fixture-meta".utf8).write(to: beta.appendingPathComponent("vehicles.meta"))
        try Data("fixture-rpf-beta".utf8).write(to: beta.appendingPathComponent("dlc.rpf"))
        try Data("fixture-rpf-optima".utf8).write(to: optima.appendingPathComponent("dlc.rpf"))
        try Data("fixture-rpf-rbtitt".utf8).write(to: rbtitt.appendingPathComponent("dlc.rpf"))
        try INRPFOrbxAutoInstallPlanner.validateDlcRPF(in: alpha)
        try INRPFOrbxAutoInstallPlanner.validateDlcRPF(in: beta)
        try INRPFOrbxAutoInstallPlanner.validateDlcRPF(in: optima)

        let missingArchive = root.appendingPathComponent("missing_rpf", isDirectory: true)
        try FileManager.default.createDirectory(at: missingArchive, withIntermediateDirectories: true)
        do {
            try INRPFOrbxAutoInstallPlanner.validateDlcRPF(in: missingArchive)
            fatalError("Package without dlc.rpf was incorrectly accepted")
        } catch INRPFOrbxAutoInstallPlanner.PlanError.missingDlcRPF(_) {
            // Expected: package must contain dlc.rpf at its root.
        }

        let names = try INRPFOrbxAutoInstallPlanner.discoverPackageNames(in: addon)
        precondition(names == ["alpha_pack", "car_2026", "optima", "Rbtitt"].sorted(), "DLC folder discovery did not return expected names")
        precondition(INRPFOrbxAutoInstallPlanner.remoteAddon == "/Data/orbx/gta/rpf/dlc_addon", "Incorrect PS4 addon path")
        precondition(INRPFOrbxAutoInstallPlanner.remoteDLClistDirectory == "/Data/orbx/gta", "Incorrect PS4 dlclist path")

        let legacyRoot = root.appendingPathComponent("PS4-Orbx-Legacy", isDirectory: true)
        let legacyData = legacyRoot.appendingPathComponent("data/orbx/gta/rpf/dlc_addon", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyData, withIntermediateDirectories: true)
        let resolvedLegacyAddon = try INRPFOrbxAutoInstallPlanner.addonFolder(in: legacyRoot)
        precondition(resolvedLegacyAddon.path == legacyData.path,
                     "Legacy lower-case data folder was not resolved")

        let gtaRoot = root.appendingPathComponent("Data/orbx/gta", isDirectory: true)
        try FileManager.default.createDirectory(at: gtaRoot, withIntermediateDirectories: true)
        let dlclistFile = gtaRoot.appendingPathComponent("dlclist.xml")
        let original = """
        <?xml version="1.0" encoding="UTF-8"?>
        <SMandatoryPacksData>
          <Paths>
            <Item>/Data/orbx/gta/rpf/dlc_addon/old_pack/</Item>
          </Paths>
        </SMandatoryPacksData>
        """
        try original.write(to: dlclistFile, atomically: true, encoding: .utf8)
        let onDiskOriginal = try String(contentsOf: dlclistFile, encoding: .utf8)
        let merged = try INRPFOrbxAutoInstallPlanner.mergedDLClist(existing: onDiskOriginal, packageNames: names)
        try merged.write(to: dlclistFile, atomically: true, encoding: .utf8)
        let onDiskMerged = try String(contentsOf: dlclistFile, encoding: .utf8)
        precondition(onDiskMerged == merged, "dlclist.xml fixture was not written correctly")
        precondition(merged.contains("/Data/orbx/gta/rpf/dlc_addon/old_pack/"), "Existing XML entries were not preserved")
        precondition(merged.contains("/Data/orbx/gta/rpf/dlc_addon/alpha_pack/"), "First package path missing")
        precondition(merged.contains("/Data/orbx/gta/rpf/dlc_addon/car_2026/"), "Second package path missing")
        precondition(merged.contains("/Data/orbx/gta/rpf/dlc_addon/optima/"), "optima package path missing")
        precondition(merged.contains("/Data/orbx/gta/rpf/dlc_addon/Rbtitt/"), "Rbtitt package path missing")

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
        print("Fixture folder: Data/orbx/gta/rpf/dlc_addon/")
        print("Fixture file: ORBX/GTA/dlclist.xml (Data/orbx/gta/dlclist.xml)")
        print("Package layout: each addon contains dlc.rpf directly; same-name wrappers are normalized.")
        print("Packages: \(names.joined(separator: ", "))")
        print("XML: existing entries preserved, paths merged, duplicate-safe, malformed XML rejected.")
    }
}
