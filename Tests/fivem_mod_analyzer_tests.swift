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
        precondition(!nonFiveM.isFiveMVehicleResource, "Plain folder was incorrectly detected as FiveM")

        let dlc = root.appendingPathComponent("dlc_pack", isDirectory: true)
        try write("rpf", to: dlc.appendingPathComponent("dlc.rpf"))
        let dlcReport = try ModAnalyzer.analyze(at: dlc)
        precondition(dlcReport.dlcFiles.count == 1, "dlc.rpf was not detected")

        print("FiveM ModAnalyzer tests passed: vehicle resource, non-FiveM folder, DLC inventory.")
    }

    private static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
