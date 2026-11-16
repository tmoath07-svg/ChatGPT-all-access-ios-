import Foundation

@main
struct FiveMModAnalyzerTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("inrpf-fivem-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        let resource = root.appendingPathComponent("test_resource", isDirectory: true)
        try write("fx_version 'cerulean'\ngame 'gta5'", to: resource.appendingPathComponent("fxmanifest.lua"))
        try write("model", to: resource.appendingPathComponent("stream").appendingPathComponent("testcar").appendingPathComponent("testcar.yft"))
        try write("texture", to: resource.appendingPathComponent("stream").appendingPathComponent("testcar").appendingPathComponent("testcar.ytd"))
        try write("<CVehicleModelInfo__InitDataList/>", to: resource.appendingPathComponent("data").appendingPathComponent("testcar").appendingPathComponent("vehicles.meta"))
        try write("<HandlingData/>", to: resource.appendingPathComponent("data").appendingPathComponent("testcar").appendingPathComponent("handling.meta"))

        let fiveM = try ModAnalyzer.analyze(at: resource)
        precondition(fiveM.isFiveMVehicleResource, "Valid FiveM vehicle resource was not detected")
        precondition(fiveM.resourceRootRelative == ".", "Direct resource root was not reported correctly")

        // Archive wrapper regression: the actual resource is nested below an arbitrary top-level folder.
        let wrapped = root.appendingPathComponent("D2A9E388", isDirectory: true)
        let nestedResource = wrapped.appendingPathComponent("rb3nasb", isDirectory: true)
        try write("fx_version 'cerulean'\ngame 'gta5'", to: nestedResource.appendingPathComponent("fxmanifest.lua"))
        try write("model-a", to: nestedResource.appendingPathComponent("stream/rb3nasb/rb3nasb.yft"))
        try write("model-b", to: nestedResource.appendingPathComponent("stream/rb3nasb2/rb3nasb2.yft"))
        try write("texture", to: nestedResource.appendingPathComponent("stream/rb3nasb1/rb3nasb1.ytd"))
        try write("<CVehicleModelInfo__InitDataList/>", to: nestedResource.appendingPathComponent("data/rb3nasb/vehicles.meta"))
        try write("<HandlingData/>", to: nestedResource.appendingPathComponent("data/rb3nasb1/handling.meta"))
        let discovered = try ModAnalyzer.discoverFiveMResourceRoot(in: wrapped)
        precondition(discovered?.standardizedFileURL == nestedResource.standardizedFileURL,
                     "Nested FiveM manifest root was not discovered")
        let nestedReport = try ModAnalyzer.analyze(at: wrapped)
        precondition(nestedReport.isFiveMVehicleResource, "Nested FiveM vehicle resource was not detected")
        precondition(nestedReport.resourceRootRelative == "rb3nasb", "Nested resource root path is incorrect")
        precondition(nestedReport.yftFiles.count == 2 && nestedReport.ytdFiles.count == 1,
                     "Nested multi-folder stream inventory is incorrect")
        precondition(nestedReport.vehicleMetaFiles.count == 2,
                     "Nested META inventory is incorrect")
        precondition(fiveM.yftFiles.count == 1 && fiveM.ytdFiles.count == 1, "YFT/YTD inventory is incorrect")
        precondition(fiveM.manifestFiles.count == 1, "FiveM manifest was not detected")

        let minimalVehicle = root.appendingPathComponent("minimal_vehicle", isDirectory: true)
        try write("game 'gta5'", to: minimalVehicle.appendingPathComponent("fxmanifest.lua"))
        try write("model", to: minimalVehicle.appendingPathComponent("stream/car/car.yft"))
        try write("<CVehicleModelInfo__InitDataList/>", to: minimalVehicle.appendingPathComponent("data/car/vehicles.meta"))
        let minimalReport = try ModAnalyzer.analyze(at: minimalVehicle)
        precondition(minimalReport.isFiveMVehicleResource,
                     "Valid vehicle resource without YTD/handling.meta should be detected")

        let plain = root.appendingPathComponent("plain", isDirectory: true)
        try write("readme", to: plain.appendingPathComponent("readme.txt"))
        let nonFiveM = try ModAnalyzer.analyze(at: plain)
        precondition(!nonFiveM.isFiveMVehicleResource && nonFiveM.fileCount == 1 && nonFiveM.dlcFiles.isEmpty,
                     "Non-vehicle inventory should retain the real file count")
        precondition(nonFiveM.reportText.contains("لم يتم التعرف على مود مركبة"),
                     "Non-vehicle diagnostic explanation is missing")

        let dlc = root.appendingPathComponent("dlc_pack", isDirectory: true)
        try write("rpf", to: dlc.appendingPathComponent("dlc.rpf"))
        try write("<CVehicleModelInfo__InitDataList/>", to: dlc.appendingPathComponent("vehicles.meta"))
        let dlcReport = try ModAnalyzer.analyze(at: dlc)
        precondition(dlcReport.dlcFiles.count == 1, "dlc.rpf was not detected")

        print("FiveM ModAnalyzer tests passed: vehicle resource, non-vehicle rejection, vehicle DLC inventory.")
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
