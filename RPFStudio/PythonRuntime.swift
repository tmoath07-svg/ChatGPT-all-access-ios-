import Foundation

enum PythonRuntimeError: LocalizedError {
    case missingHome
    case missingEngine
    case executionFailed(Int32)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .missingHome: return "مجلد Python غير موجود داخل التطبيق."
        case .missingEngine: return "ملف محرك الفحص غير موجود."
        case .executionFailed(let code): return "فشل تنفيذ سكربت Python (\(code))."
        case .outputMissing: return "اشتغل Python لكن ما أنشأ تقرير الفحص."
        }
    }
}

final class PythonRuntime {
    static let shared = PythonRuntime()
    private let lock = NSLock()

    private init() {}

    func inspect(file: URL) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        guard let pythonHome = Bundle.main.resourceURL?.appendingPathComponent("python", isDirectory: true),
              FileManager.default.fileExists(atPath: pythonHome.path) else {
            throw PythonRuntimeError.missingHome
        }
        guard let engine = Bundle.main.url(forResource: "rpf_inspect", withExtension: "py", subdirectory: "engine") else {
            throw PythonRuntimeError.missingEngine
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpf-report-\(UUID().uuidString).txt")
        try? FileManager.default.removeItem(at: output)

        let result = RPFRunPythonScript(pythonHome.path, engine.path, file.path, output.path)
        guard result == 0 else {
            throw PythonRuntimeError.executionFailed(result)
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw PythonRuntimeError.outputMissing
        }
        return try String(contentsOf: output, encoding: .utf8)
    }
}
