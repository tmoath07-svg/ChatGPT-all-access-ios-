import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("inrpf-ftp-plan-\(UUID().uuidString)", isDirectory: true)
defer { try? fm.removeItem(at: root) }
try fm.createDirectory(at: root.appendingPathComponent("stream/models", isDirectory: true), withIntermediateDirectories: true)
try fm.createDirectory(at: root.appendingPathComponent("data", isDirectory: true), withIntermediateDirectories: true)
try fm.createDirectory(at: root.appendingPathComponent("empty-folder", isDirectory: true), withIntermediateDirectories: true)
try Data("meta".utf8).write(to: root.appendingPathComponent("data/vehicles.meta"))
try Data("model".utf8).write(to: root.appendingPathComponent("stream/models/car.yft"))
try Data("hidden".utf8).write(to: root.appendingPathComponent(".hidden-file"))

let plan = try INRPFDirectoryUploadPlanner.plan(for: root)
let paths = plan.map(\.relativePath)
require(paths.contains("data"), "include data directory")
require(paths.contains("data/vehicles.meta"), "include metadata file")
require(paths.contains("stream/models/car.yft"), "include nested model file")
require(paths.contains("empty-folder"), "include empty directories")
require(paths.contains(".hidden-file"), "preserve hidden files")
require(plan.first(where: { $0.relativePath == "data" })?.isDirectory == true, "mark directory entries")
require(plan.first(where: { $0.relativePath == "data/vehicles.meta" })?.isDirectory == false, "mark file entries")
require(paths == paths.sorted { a, b in
    let da = a.split(separator: "/").count
    let db = b.split(separator: "/").count
    if da != db { return da < db }
    let aDir = plan.first(where: { $0.relativePath == a })?.isDirectory ?? false
    let bDir = plan.first(where: { $0.relativePath == b })?.isDirectory ?? false
    if aDir != bDir { return aDir }
    return a < b
}, "sort parents before descendants")

let missing = root.appendingPathComponent("missing", isDirectory: true)
do {
    _ = try INRPFDirectoryUploadPlanner.plan(for: missing)
    fatalError("missing folder should fail")
} catch { }

print("FTP directory upload planner tests passed: \(plan.count) entries")
