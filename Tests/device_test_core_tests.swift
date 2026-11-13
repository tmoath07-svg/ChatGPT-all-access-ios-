import Foundation

@main
struct INRPFDeviceTestCoreTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("INRPF-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let report = INRPFDeviceTestCore.run(rootURL: root, appVersion: "5.20", buildNumber: "58", platform: "CI", deviceModel: "GitHub Actions")
        precondition(report.results.count == 5)
        precondition(report.allPassed, report.text)
        precondition(report.text.contains("INRPF DEVICE TEST REPORT"))
        precondition(report.text.contains("Version=5.20, Build=58"))
        print("INRPF device test core: all tests passed")
    }
}
