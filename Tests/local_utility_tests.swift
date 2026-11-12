import Foundation

@main
struct LocalUtilityTests {
    static func main() throws {
        try testSafeNames()
        try testHexDecoder()
        try testDependencyScanner()
        print("LOCAL UTILITY TESTS: PASS")
    }

    private static func testSafeNames() throws {
        let basic = INRPFLocalUtilityCore.safePackageName("BMW M5 Competition", existingNames: [])
        precondition(basic == "bmw_m5_competition", "Unexpected safe name: \(basic)")
        let unique = INRPFLocalUtilityCore.safePackageName("BMW M5 Competition", existingNames: ["bmw_m5_competition"])
        precondition(unique == "bmw_m5_competition_2", "Collision suffix was not added: \(unique)")
        let arabic = INRPFLocalUtilityCore.safePackageName("سيارة جديدة", existingNames: [])
        precondition(arabic == "dlc_pack", "Non-ASCII fallback is not safe")
    }

    private static func testHexDecoder() throws {
        let data = try INRPFLocalUtilityCore.decodeHex("0A FF 12\n7b")
        precondition(Array(data) == [0x0A, 0xFF, 0x12, 0x7B], "Hex bytes were decoded incorrectly")
        do {
            _ = try INRPFLocalUtilityCore.decodeHex("0A GG")
            fatalError("Invalid hex token was accepted")
        } catch {
            // Expected.
        }
    }

    private static func testDependencyScanner() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("inrpf-dependency-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("data", isDirectory: true), withIntermediateDirectories: true)
        try Data("meta".utf8).write(to: root.appendingPathComponent("data/vehicles.meta"))
        try Data("print('client')".utf8).write(to: root.appendingPathComponent("client.lua"))
        let manifest = """
        fx_version 'cerulean'
        game 'gta5'
        dependency 'ox_lib'
        dependencies { 'oxmysql', 'ox_lib' }
        files { 'data/vehicles.meta', 'ui/index.html' }
        client_script 'client.lua'
        """
        try Data(manifest.utf8).write(to: root.appendingPathComponent("fxmanifest.lua"))
        let report = try INRPFLocalUtilityCore.dependencyReport(at: root)
        precondition(report.contains("ox_lib"), "External dependency was not detected")
        precondition(report.contains("oxmysql"), "Dependencies block was not parsed")
        precondition(report.contains("ui/index.html"), "Missing local file was not detected")
        precondition(!report.contains("ox_lib (مسار خارج المورد)"), "External dependency was incorrectly treated as a local path")
    }
}
