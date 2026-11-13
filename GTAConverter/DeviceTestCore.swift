import Foundation

struct INRPFDeviceTestResult: Identifiable {
    let id: String
    let title: String
    let passed: Bool
    let details: String
}

struct INRPFDeviceTestReport {
    let generatedAt: Date
    let appVersion: String
    let buildNumber: String
    let platform: String
    let deviceModel: String
    let results: [INRPFDeviceTestResult]
    var passedCount: Int { results.filter(\.passed).count }
    var failedCount: Int { results.filter { !$0.passed }.count }
    var allPassed: Bool { !results.isEmpty && failedCount == 0 }
    var text: String {
        let date = ISO8601DateFormatter().string(from: generatedAt)
        let lines = ["INRPF DEVICE TEST REPORT", "Generated: \(date)",
            "App version: \(appVersion)", "Build: \(buildNumber)",
            "Platform: \(platform)", "Device: \(deviceModel)",
            "Result: \(passedCount)/\(results.count) passed; \(failedCount) failed", "",
            results.map { "\($0.passed ? "PASS" : "FAIL") | \($0.title) | \($0.details)" }.joined(separator: "\n")]
        return lines.joined(separator: "\n")
    }
}

enum INRPFDeviceTestCore {
    static func run(rootURL: URL, appVersion: String, buildNumber: String,
                    platform: String, deviceModel: String) -> INRPFDeviceTestReport {
        let fm = FileManager.default
        var results: [INRPFDeviceTestResult] = []
        let folder = rootURL.appendingPathComponent("INRPF-Test-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            results.append(.init(id: "directory", title: "إنشاء مجلد اختبار", passed: true, details: "تم إنشاء مجلد مؤقت."))
        } catch {
            results.append(.init(id: "directory", title: "إنشاء مجلد اختبار", passed: false, details: error.localizedDescription))
        }
        if fm.fileExists(atPath: folder.path) {
            let file = folder.appendingPathComponent("probe.txt")
            let expected = Data("INRPF_DEVICE_TEST_OK".utf8)
            do {
                try expected.write(to: file, options: .atomic)
                guard try Data(contentsOf: file) == expected else { throw NSError(domain: "INRPF.Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "اختلاف البيانات بعد القراءة."]) }
                results.append(.init(id: "io", title: "كتابة وقراءة ملف", passed: true, details: "تطابقت البيانات بعد القراءة."))
            } catch {
                results.append(.init(id: "io", title: "كتابة وقراءة ملف", passed: false, details: error.localizedDescription))
            }
            do {
                try fm.removeItem(at: folder)
                results.append(.init(id: "cleanup", title: "تنظيف ملفات الاختبار", passed: true, details: "حُذف المجلد المؤقت."))
            } catch {
                results.append(.init(id: "cleanup", title: "تنظيف ملفات الاختبار", passed: false, details: error.localizedDescription))
            }
        } else {
            results.append(.init(id: "io", title: "كتابة وقراءة ملف", passed: false, details: "تعذر إنشاء مجلد الاختبار."))
            results.append(.init(id: "cleanup", title: "تنظيف ملفات الاختبار", passed: true, details: "لا توجد ملفات مؤقتة."))
        }
        results.append(.init(id: "metadata", title: "بيانات إصدار التطبيق", passed: !appVersion.isEmpty && !buildNumber.isEmpty, details: "Version=\(appVersion), Build=\(buildNumber)"))
        results.append(.init(id: "platform", title: "بيئة التشغيل", passed: !platform.isEmpty, details: platform))
        return .init(generatedAt: Date(), appVersion: appVersion, buildNumber: buildNumber,
                     platform: platform, deviceModel: deviceModel, results: results)
    }
}
