import Foundation
import Python

enum PythonRuntimeError: LocalizedError {
    case missingHome
    case missingEngine
    case startupFailed(Int32)
    case executionFailed(Int32)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .missingHome: return "مجلد Python غير موجود داخل التطبيق."
        case .missingEngine: return "ملف محرك الفحص غير موجود."
        case .startupFailed(let code): return "تعذر تشغيل Python (\(code))."
        case .executionFailed(let code): return "فشل تنفيذ سكربت Python (\(code))."
        case .outputMissing: return "اشتغل Python لكن ما أنشأ تقرير الفحص."
        }
    }
}

final class PythonRuntime {
    static let shared = PythonRuntime()
    private var initialized = false
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

        if !initialized {
            setenv("PYTHONHOME", pythonHome.path, 1)
            setenv("PYTHONPATH", engine.deletingLastPathComponent().path, 1)
            Py_Initialize()
            guard Py_IsInitialized() != 0 else {
                throw PythonRuntimeError.startupFailed(-1)
            }
            initialized = true
        }

        let script = engine.path
        let input = file.path
        let report = output.path
        let code = """
import sys, runpy, contextlib
sys.argv = [\(Self.pythonString(script)), \(Self.pythonString(input))]
with open(\(Self.pythonString(report)), "w", encoding="utf-8") as report_file:
    with contextlib.redirect_stdout(report_file), contextlib.redirect_stderr(report_file):
        runpy.run_path(\(Self.pythonString(script)), run_name="__main__")
"""
        let result = code.withCString { PyRun_SimpleStringFlags($0, nil) }
        guard result == 0 else {
            throw PythonRuntimeError.executionFailed(result)
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw PythonRuntimeError.outputMissing
        }
        return try String(contentsOf: output, encoding: .utf8)
    }

    private static func pythonString(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }
}
