import Foundation

@main
struct FTPDirectoryUploadTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() throws {
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

        let sorted = plan.sorted { a, b in
            let da = a.relativePath.split(separator: "/").count
            let db = b.relativePath.split(separator: "/").count
            if da != db { return da < db }
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.relativePath < b.relativePath
        }
        require(paths == sorted.map(\.relativePath), "sort parents before descendants")

        // Virtual ORBX FTP tree: this is a local fixture representing the
        // remote GoldHEN directory, not a live console or network connection.
        let orbx = root.appendingPathComponent("data/orbx/gta/rpf/dlc_addon/Rbtitt", isDirectory: true);
        try fm.createDirectory(at: orbx.appendingPathComponent("stream", isDirectory: true),
                               withIntermediateDirectories: true);
        try Data("synthetic-dlc-rpf".utf8).write(to: orbx.appendingPathComponent("dlc.rpf"));
        try Data("synthetic-vehicle-meta".utf8).write(to: orbx.appendingPathComponent("vehicles.meta"));
        try Data("synthetic-model".utf8).write(to: orbx.appendingPathComponent("stream/Rbtitt.oft"));
        let virtualFTPPlan = try INRPFDirectoryUploadPlanner.plan(for: root)
        let virtualFTPPaths = Set(virtualFTPPlan.map(\\.relativePath))
        require(virtualFTPPaths.contains("data/orbx/gta/rpf/dlc_addon/Rbtitt/dlc.rpf"),
                "virtual ORBX FTP tree includes the package dlc.rpf")
        require(virtualFTPPaths.contains("data/orbx/gta/rpf/dlc_addon/Rbtitt/vehicles.meta"),
                "virtual ORBX FTP tree includes vehicle metadata")
        require(virtualFTPPaths.contains("data/orbx/gta/rpf/dlc_addon/Rbtitt/stream/Rbtitt.oft"),
                "virtual ORBX FTP tree includes the vehicle model")
        require(virtualFTPPlan.first(where: {
            $0.relativePath == "data/orbx/gta/rpf/dlc_addon/Rbtitt"
        })?.isDirectory == true, "virtual FTP package directory is planned before its contents")

        let missing = root.appendingPathComponent("missing", isDirectory: true)
        var rejectedMissing = false
        do {
            _ = try INRPFDirectoryUploadPlanner.plan(for: missing)
        } catch {
            rejectedMissing = true
        }
        require(rejectedMissing, "reject a missing directory")

        print("FTP directory upload planner tests passed: \(plan.count) entries")
    }
}
