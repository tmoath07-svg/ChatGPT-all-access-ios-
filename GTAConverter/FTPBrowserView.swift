import SwiftUI
import UniformTypeIdentifiers

private enum FTPFailure: LocalizedError {
    case response(String)
    var errorDescription: String? {
        switch self {
        case .response(let value): return value
        }
    }
}

private final class INRPFtpClient {
    private var host = ""
    private var port: UInt16 = 2121
    private var username = "anonymous"
    private var password = ""

    func connect(host: String, port: UInt16, username: String, password: String) async throws {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        _ = try await Task.detached(priority: .userInitiated) {
            try LocalEngineBridge.ftpConnect(host: host, port: port, username: username, password: password)
        }.value
    }

    func disconnect() {
        host = ""
        port = 2121
        username = "anonymous"
        password = ""
    }

    func list(path: String) async throws -> [(name: String, isDirectory: Bool, size: String)] {
        let host = self.host, port = self.port, username = self.username, password = self.password
        let result = try await Task.detached(priority: .userInitiated) {
            try LocalEngineBridge.ftpList(host: host, port: port, username: username, password: password, path: path)
        }.value
        let values = result["entries"] as? [[String: Any]] ?? []
        return values.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return (name: name, isDirectory: item["isDirectory"] as? Bool ?? false,
                    size: item["size"] as? String ?? "")
        }
    }

    func changeDirectory(path: String) async throws {
        _ = try await list(path: path)
    }

    func makeDirectory(_ name: String, path: String) async throws {
        let host = self.host, port = self.port, username = self.username, password = self.password
        _ = try await Task.detached(priority: .userInitiated) {
            try LocalEngineBridge.ftpMakeDirectory(host: host, port: port, username: username,
                                                    password: password, path: path, name: name)
        }.value
    }

    func upload(fileURL: URL, remoteName: String, path: String) async throws {
        let host = self.host, port = self.port, username = self.username, password = self.password
        _ = try await Task.detached(priority: .userInitiated) {
            try LocalEngineBridge.ftpUpload(host: host, port: port, username: username,
                                            password: password, path: path, name: remoteName, localFile: fileURL)
        }.value
    }

    func download(remoteName: String, path: String, to destination: URL) async throws {
        let host = self.host, port = self.port, username = self.username, password = self.password
        _ = try await Task.detached(priority: .userInitiated) {
            try LocalEngineBridge.ftpDownload(host: host, port: port, username: username,
                                              password: password, path: path, name: remoteName,
                                              destination: destination)
        }.value
    }
}

@MainActor
private final class FTPBrowserModel: ObservableObject {
    @Published var host = ""
    @Published var port = "2121"
    @Published var username = "anonymous"
    @Published var password = ""
    @Published var currentPath = "/"
    @Published var entries: [(name: String, isDirectory: Bool, size: String)] = []
    @Published var status = "أدخل عنوان PS4 وفعّل FTP في GoldHEN."
    @Published var error = ""
    @Published var isConnected = false
    @Published var isBusy = false
    @Published var downloadedFile: URL?
    let client = INRPFtpClient()

    func connect() {
        Task {
            isBusy = true
            error = ""
            do {
                guard let portValue = UInt16(port), !host.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw FTPFailure.response("تحقق من IP والمنفذ.")
                }
                try await client.connect(host: host.trimmingCharacters(in: .whitespaces), port: portValue,
                                         username: username, password: password)
                isConnected = true
                currentPath = "/"
                try await refresh()
                status = "تم الاتصال بجهاز PS4."
            } catch {
                self.error = error.localizedDescription
                isConnected = false
                client.disconnect()
            }
            isBusy = false
        }
    }

    func disconnect() {
        client.disconnect()
        isConnected = false
        entries = []
        status = "تم قطع الاتصال."
    }

    func refresh() async throws {
        entries = try await client.list(path: currentPath)
    }

    func open(_ entry: (name: String, isDirectory: Bool, size: String)) {
        guard entry.isDirectory else { return }
        Task {
            isBusy = true
            do {
                let nextPath = currentPath == "/" ? "/" + entry.name : currentPath + "/" + entry.name
                try await client.changeDirectory(path: nextPath)
                currentPath = nextPath
                try await refresh()
                error = ""
            } catch let caughtError { self.error = caughtError.localizedDescription }
            isBusy = false
        }
    }

    func goUp() {
        Task {
            isBusy = true
            do {
                let parts = currentPath.split(separator: "/")
                let parentPath = parts.dropLast().isEmpty ? "/" : "/" + parts.dropLast().joined(separator: "/")
                try await client.changeDirectory(path: parentPath)
                currentPath = parentPath
                try await refresh()
                error = ""
            } catch let caughtError { self.error = caughtError.localizedDescription }
            isBusy = false
        }
    }

    func upload(_ url: URL) {
        let scopeStarted = url.startAccessingSecurityScopedResource()
        Task {
            defer { if scopeStarted { url.stopAccessingSecurityScopedResource() } }
            isBusy = true
            error = ""
            do {
                let localURL = try await Task.detached(priority: .userInitiated) {
                    try FileImportService.importItem(from: url, category: "Imports",
                                                     securityScopeAlreadyStarted: scopeStarted)
                }.value

                var sourceIsDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &sourceIsDirectory) else {
                    throw FTPFailure.response("العنصر المستورد لم يعد موجوداً.")
                }

                if sourceIsDirectory.boolValue {
                    let result = try await uploadDirectory(
                        localRoot: localURL,
                        remoteName: url.lastPathComponent,
                        remoteParentPath: currentPath
                    )
                    try await refresh()
                    status = "تم رفع المجلد \(url.lastPathComponent): \(result.files) ملف و\(result.folders) مجلد."
                } else {
                    try await client.upload(fileURL: localURL, remoteName: url.lastPathComponent, path: currentPath)
                    try await refresh()
                    status = "تم رفع الملف \(url.lastPathComponent)."
                }
            } catch let caughtError {
                self.error = caughtError.localizedDescription
            }
            isBusy = false
        }
    }

    private func uploadDirectory(localRoot: URL, remoteName: String,
                                 remoteParentPath: String) async throws -> (files: Int, folders: Int) {
        let fm = FileManager.default
        var rootIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: localRoot.path, isDirectory: &rootIsDirectory),
              rootIsDirectory.boolValue else {
            throw FTPFailure.response("المجلد المحلي غير صالح.")
        }

        let safeRootName = URL(fileURLWithPath: remoteName).lastPathComponent
        guard !safeRootName.isEmpty, safeRootName != ".", safeRootName != "..",
              !safeRootName.contains("/") else {
            throw FTPFailure.response("اسم المجلد غير صالح.")
        }

        try await client.makeDirectory(safeRootName, path: remoteParentPath)
        let remoteRoot = Self.joinRemotePath(remoteParentPath, safeRootName)
        guard let enumerator = fm.enumerator(
            at: localRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw FTPFailure.response("تعذر قراءة محتويات المجلد المحلي.")
        }

        var entries: [(url: URL, components: [String], isDirectory: Bool)] = []
        let localPrefix = localRoot.standardizedFileURL.path + "/"
        var visited = 0
        for case let item as URL in enumerator {
            visited += 1
            guard visited <= 100_000 else {
                throw FTPFailure.response("المجلد يحتوي عدداً كبيراً جداً من العناصر.")
            }
            let standardized = item.standardizedFileURL.path
            guard standardized.hasPrefix(localPrefix) else {
                throw FTPFailure.response("تم رفض مسار عنصر خارج المجلد المحدد.")
            }
            let relative = String(standardized.dropFirst(localPrefix.count))
            let components = relative.split(separator: "/").map(String.init)
            guard !components.isEmpty,
                  !components.contains(".."),
                  !components.contains("."),
                  components.allSatisfy({ !$0.isEmpty && !$0.contains("\\") }) else {
                throw FTPFailure.response("يحتوي المجلد على مسار غير صالح.")
            }

            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { continue }
            entries.append((item, components, values.isDirectory == true))
        }

        entries.sort {
            if $0.components.count != $1.components.count {
                return $0.components.count < $1.components.count
            }
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.components.joined(separator: "/") < $1.components.joined(separator: "/")
        }

        var fileCount = 0
        var folderCount = 1
        for entry in entries {
            let name = entry.components[entry.components.count - 1]
            let parentRelative = entry.components.dropLast().joined(separator: "/")
            let remoteParent = parentRelative.isEmpty
                ? remoteRoot
                : Self.joinRemotePath(remoteRoot, parentRelative)

            if entry.isDirectory {
                try await client.makeDirectory(name, path: remoteParent)
                folderCount += 1
            } else {
                try await client.upload(fileURL: entry.url, remoteName: name, path: remoteParent)
                fileCount += 1
            }
        }
        return (fileCount, folderCount)
    }

    private static func joinRemotePath(_ base: String, _ component: String) -> String {
        let cleanBase = base.isEmpty ? "/" : base
        let cleanComponent = component.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !cleanComponent.isEmpty else { return cleanBase }
        return cleanBase == "/" ? "/" + cleanComponent : cleanBase + "/" + cleanComponent
    }

    func download(_ name: String) {
        Task {
            isBusy = true
            error = ""
            do {
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let folder = documents.appendingPathComponent("GTA Converter/Downloads", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let safeName = URL(fileURLWithPath: name).lastPathComponent
                let file = folder.appendingPathComponent(safeName)
                try await client.download(remoteName: name, path: currentPath, to: file)
                downloadedFile = file
                status = "تم تنزيل \(safeName)"
            } catch let caughtError { self.error = caughtError.localizedDescription }
            isBusy = false
        }
    }

    func createFolder(_ name: String) {
        Task {
            isBusy = true
            do {
                try await client.makeDirectory(name, path: currentPath)
                try await refresh()
                error = ""
            } catch let caughtError { self.error = caughtError.localizedDescription }
            isBusy = false
        }
    }
}

struct FTPBrowserView: View {
    @StateObject private var model = FTPBrowserModel()
    @State private var showingUpload = false
    @State private var showingNewFolder = false
    @State private var folderName = ""

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    connectionPanel
                    if model.isConnected {
                        browserPanel
                    }
                    if !model.status.isEmpty {
                        Text(model.status).font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    if !model.error.isEmpty {
                        Text(model.error).font(.caption).foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                    if model.isBusy { ProgressView().tint(.white).frame(maxWidth: .infinity) }
                }
                .padding(16)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("FTP جهاز PS4")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingUpload) {
            INRPFDocumentPickerPresenter(
                contentTypes: [.item, .folder],
                onCompletion: { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first { model.upload(url) }
                    case .failure(let failure):
                        model.error = failure.localizedDescription
                    }
                }
            )
            .ignoresSafeArea()
        }
        .alert("مجلد جديد", isPresented: $showingNewFolder) {
            TextField("اسم المجلد", text: $folderName)
            Button("إنشاء") {
                let safe = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !safe.isEmpty, !safe.contains("/"), !safe.contains("..") else { return }
                model.createFolder(safe)
                folderName = ""
            }
            Button("إلغاء", role: .cancel) { folderName = "" }
        } message: {
            Text("سيُنشأ المجلد داخل المسار الحالي على PS4.")
        }
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("اتصال FTP محلي", systemImage: "network")
                .font(.headline).foregroundStyle(.white)
            TextField("IP جهاز PS4 مثل 192.168.1.20", text: $model.host)
                .keyboardType(.decimalPad).textInputAutocapitalization(.never)
                .padding(12).background(.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 11))
                .environment(\.layoutDirection, .leftToRight)
            HStack {
                TextField("المنفذ", text: $model.port).keyboardType(.numberPad)
                TextField("اسم المستخدم", text: $model.username).textInputAutocapitalization(.never)
            }
            .padding(12).background(.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 11))
            SecureField("كلمة المرور (اتركها فارغة إذا Anonymous)", text: $model.password)
                .padding(12).background(.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 11))
            HStack {
                Button { model.connect() } label: {
                    Label("اتصال", systemImage: "link").frame(maxWidth: .infinity).padding(12)
                        .background(Color.purple.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: 12))
                }.disabled(model.isBusy || model.isConnected)
                Button { model.disconnect() } label: {
                    Label("قطع", systemImage: "xmark").frame(maxWidth: .infinity).padding(12)
                        .background(.white.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                }.disabled(!model.isConnected)
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            Text("تأكد أن iPad وPS4 على نفس الشبكة وأن خادم FTP في GoldHEN مفعّل. المنفذ الافتراضي غالبًا 2121.")
                .font(.caption2).foregroundStyle(.white.opacity(0.55))
        }
        .padding(16).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var browserPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ملفات PS4", systemImage: "folder.fill").font(.headline)
                Spacer()
                Button { model.goUp() } label: { Image(systemName: "arrow.up").padding(9).background(.white.opacity(0.1)).clipShape(Circle()) }
                Button { Task { try? await model.refresh() } } label: { Image(systemName: "arrow.clockwise").padding(9).background(.white.opacity(0.1)).clipShape(Circle()) }
            }
            Text(model.currentPath).font(.caption.monospaced()).foregroundStyle(.purple).textSelection(.enabled)
            HStack {
                Button { showingUpload = true } label: { Label("رفع ملف", systemImage: "arrow.up.doc").frame(maxWidth: .infinity).padding(11).background(.purple.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 11)) }
                Button { showingNewFolder = true } label: { Label("مجلد جديد", systemImage: "folder.badge.plus").frame(maxWidth: .infinity).padding(11).background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 11)) }
            }.buttonStyle(.plain).font(.caption.bold())
            ForEach(Array(model.entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(entry.isDirectory ? .yellow : .white.opacity(0.7))
                    Button { model.open(entry) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).lineLimit(1)
                            if !entry.isDirectory && !entry.size.isEmpty {
                                Text(entry.size).font(.caption2).foregroundStyle(.white.opacity(0.45))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).disabled(!entry.isDirectory)
                    if !entry.isDirectory {
                        Button { model.download(entry.name) } label: {
                            Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(.purple)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(10).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if model.entries.isEmpty {
                Text("المجلد فارغ أو لم تُرجع قائمة الملفات نتائج.").font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            if let file = model.downloadedFile {
                ShareLink(item: file) {
                    Label("مشاركة الملف المنزّل: \(file.lastPathComponent)", systemImage: "square.and.arrow.up")
                        .font(.caption.bold()).frame(maxWidth: .infinity).padding(11)
                        .background(.green.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .padding(16).background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
