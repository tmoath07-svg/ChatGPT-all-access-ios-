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
        precondition(fiveM.yftFiles.count == 1 && fiveM.ytdFiles.count == 1, "YFT/YTD inventory is incorrect")
        precondition(fiveM.manifestFiles.count == 1, "FiveM manifest was not detected")

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
