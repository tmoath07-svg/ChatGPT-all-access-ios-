import SwiftUI
import Network
import UniformTypeIdentifiers

private enum FTPFailure: LocalizedError {
    case response(String)
    case invalidPassiveResponse
    case disconnected

    var errorDescription: String? {
        switch self {
        case .response(let value): return value
        case .invalidPassiveResponse: return "تعذر قراءة عنوان اتصال FTP السلبي."
        case .disconnected: return "انقطع اتصال FTP."
        }
    }
}

private final class INRPFtpClient {
    private let queue = DispatchQueue(label: "com.tmoath07.inrpf.ftp")
    private var control: NWConnection?
    private var host = ""
    private var port: UInt16 = 2121

    func connect(host: String, port: UInt16, username: String, password: String) async throws {
        disconnect()
        self.host = host
        self.port = port
        let connection = makeConnection(host: host, port: port)
        control = connection
        try await waitUntilReady(connection)
        let greeting = try await readReply(connection)
        try Self.expectSuccess(greeting, codes: [220])
        let userReply = try await command("USER \(username)")
        if userReply.hasPrefix("331") {
            let passReply = try await command("PASS \(password)")
            try Self.expectSuccess(passReply, codes: [230, 202])
        } else {
            try Self.expectSuccess(userReply, codes: [230, 202])
        }
        _ = try await command("TYPE I")
    }

    func disconnect() {
        control?.cancel()
        control = nil
    }

    func list(path: String) async throws -> [(name: String, isDirectory: Bool, size: String)] {
        let dataConnection = try await openPassiveConnection()
        let reply = try await command("MLSD \(path.isEmpty ? "." : path)")
        try Self.expectPreliminary(reply)
        let data = try await receiveAll(dataConnection)
        dataConnection.cancel()
        let completion = try await readReply(try requireControl())
        try Self.expectSuccess(completion, codes: [226, 250])
        let text = String(decoding: data, as: UTF8.self)
        let entries = text.split(whereSeparator: \.isNewline).compactMap { raw -> (String, Bool, String)? in
            let line = String(raw)
            guard let separator = line.firstIndex(of: " ") else { return nil }
            let facts = line[..<separator].lowercased()
            let name = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != ".", name != ".." else { return nil }
            let isDirectory = facts.contains("type=dir")
            let size = facts.split(separator: ";").first(where: { $0.hasPrefix("size=") }).map { String($0.dropFirst(5)) } ?? ""
            return (name, isDirectory, size)
        }
        if !entries.isEmpty { return entries.map { (name: $0.0, isDirectory: $0.1, size: $0.2) } }
        return try await listFallback(path: path)
    }

    private func listFallback(path: String) async throws -> [(name: String, isDirectory: Bool, size: String)] {
        let dataConnection = try await openPassiveConnection()
        let reply = try await command("LIST \(path.isEmpty ? "." : path)")
        try Self.expectPreliminary(reply)
        let data = try await receiveAll(dataConnection)
        dataConnection.cancel()
        let completion = try await readReply(try requireControl())
        try Self.expectSuccess(completion, codes: [226, 250])
        return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { raw in
            let parts = String(raw).split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 9 else { return nil }
            let name = parts.dropFirst(8).joined(separator: " ")
            guard name != ".", name != ".." else { return nil }
            let isDirectory = parts[0].hasPrefix("d")
            return (name: name, isDirectory: isDirectory, size: isDirectory ? "" : parts[4])
        }
    }

    func makeDirectory(_ name: String) async throws {
        let reply = try await command("MKD \(name)")
        try Self.expectSuccess(reply, codes: [257, 250])
    }

    func changeDirectory(_ path: String) async throws {
        let reply = try await command("CWD \(path)")
        try Self.expectSuccess(reply, codes: [250])
    }

    func upload(data: Data, remoteName: String) async throws {
        let dataConnection = try await openPassiveConnection()
        let reply = try await command("STOR \(remoteName)")
        try Self.expectPreliminary(reply)
        try await send(data, on: dataConnection)
        dataConnection.cancel()
        let completion = try await readReply(try requireControl())
        try Self.expectSuccess(completion, codes: [226, 250])
    }

    func download(remoteName: String) async throws -> Data {
        let dataConnection = try await openPassiveConnection()
        let reply = try await command("RETR \(remoteName)")
        try Self.expectPreliminary(reply)
        let data = try await receiveAll(dataConnection)
        dataConnection.cancel()
        let completion = try await readReply(try requireControl())
        try Self.expectSuccess(completion, codes: [226, 250])
        return data
    }

    private func requireControl() throws -> NWConnection {
        guard let control else { throw FTPFailure.disconnected }
        return control
    }

    private func command(_ value: String) async throws -> String {
        let connection = try requireControl()
        try await send(Data((value + "\r\n").utf8), on: connection)
        return try await readReply(connection)
    }

    private func openPassiveConnection() async throws -> NWConnection {
        let response = try await command("PASV")
        try Self.expectSuccess(response, codes: [227])
        guard let open = response.firstIndex(of: "("), let close = response[open...].firstIndex(of: ")") else {
            throw FTPFailure.invalidPassiveResponse
        }
        let numbers = response[response.index(after: open)..<close].split(separator: ",").compactMap { UInt16($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 6, numbers[0] <= 255, numbers[1] <= 255, numbers[2] <= 255, numbers[3] <= 255,
              numbers[4] <= 255, numbers[5] <= 255 else { throw FTPFailure.invalidPassiveResponse }
        let dataHost = numbers[0...3].map(String.init).joined(separator: ".")
        let dataPort = numbers[4] * 256 + numbers[5]
        let connection = makeConnection(host: dataHost, port: dataPort)
        try await waitUntilReady(connection)
        return connection
    }

    private func makeConnection(host: String, port: UInt16) -> NWConnection {
        NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }

    private func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var resumed = false
            connection.stateUpdateHandler = { state in
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    resumed = true
                    continuation.resume(throwing: FTPFailure.disconnected)
                default: break
                }
            }
            connection.start(queue: self.queue)
        }
    }

    private func send(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func readReply(_ connection: NWConnection) async throws -> String {
        var buffer = Data()
        while true {
            let chunk = try await receiveChunk(connection)
            buffer.append(chunk)
            guard let text = String(data: buffer, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\r\n")
            if let first = lines.first, first.count >= 3 {
                let code = String(first.prefix(3))
                if first.count >= 4 && first[first.index(first.startIndex, offsetBy: 3)] == "-" {
                    if lines.dropFirst().contains(where: { $0.hasPrefix(code + " ") }) {
                        return text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else if lines.count > 1 {
                    return text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    private func receiveChunk(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else if complete { continuation.resume(throwing: FTPFailure.disconnected) }
                else { continuation.resume(throwing: FTPFailure.disconnected) }
            }
        }
    }

    private func receiveAll(_ connection: NWConnection) async throws -> Data {
        var result = Data()
        while true {
            let chunk: Data? = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else if complete { continuation.resume(returning: nil) }
                    else { continuation.resume(returning: nil) }
                }
            }
            guard let chunk else { break }
            result.append(chunk)
        }
        return result
    }

    private static func expectSuccess(_ response: String, codes: [Int]) throws {
        let code = Int(response.prefix(3)) ?? -1
        guard codes.contains(code) else { throw FTPFailure.response(response) }
    }

    private static func expectPreliminary(_ response: String) throws {
        let code = Int(response.prefix(3)) ?? -1
        guard code == 125 || code == 150 else { throw FTPFailure.response(response) }
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
                try await client.changeDirectory(entry.name)
                currentPath = currentPath == "/" ? "/" + entry.name : currentPath + "/" + entry.name
                try await refresh()
                error = ""
            } catch { error = error.localizedDescription }
            isBusy = false
        }
    }

    func goUp() {
        Task {
            isBusy = true
            do {
                try await client.changeDirectory("..")
                let parts = currentPath.split(separator: "/")
                currentPath = parts.dropLast().isEmpty ? "/" : "/" + parts.dropLast().joined(separator: "/")
                try await refresh()
                error = ""
            } catch { error = error.localizedDescription }
            isBusy = false
        }
    }

    func upload(_ url: URL) {
        Task {
            isBusy = true
            error = ""
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try await client.upload(data: data, remoteName: url.lastPathComponent)
                try await refresh()
                status = "تم رفع \(url.lastPathComponent)"
            } catch { error = error.localizedDescription }
            isBusy = false
        }
    }

    func download(_ name: String) {
        Task {
            isBusy = true
            error = ""
            do {
                let data = try await client.download(remoteName: name)
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("INRPF-FTP", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let safeName = URL(fileURLWithPath: name).lastPathComponent
                let file = folder.appendingPathComponent(safeName)
                try data.write(to: file, options: .atomic)
                downloadedFile = file
                status = "تم تنزيل \(safeName)"
            } catch { error = error.localizedDescription }
            isBusy = false
        }
    }

    func createFolder(_ name: String) {
        Task {
            isBusy = true
            do {
                try await client.makeDirectory(name)
                try await refresh()
                error = ""
            } catch { error = error.localizedDescription }
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
        .fileImporter(isPresented: $showingUpload, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { model.upload(url) }
            if case .failure(let failure) = result { model.error = failure.localizedDescription }
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
