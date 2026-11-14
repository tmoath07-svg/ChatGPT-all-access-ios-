import SwiftUI
import SwiftArchive
import UniformTypeIdentifiers
import Security
import UIKit
import PhotosUI

private struct GHDeviceCode: Decodable {
    let device_code: String
    let user_code: String
    let verification_uri: String
    let expires_in: Int
    let interval: Int
}
private struct GHTokenResponse: Decodable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Int?
    let refresh_token_expires_in: Int?
    let error: String?
    let error_description: String?
}
private struct GHStoredToken: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
}
private struct GHUser: Decodable { let login: String }
private struct GHRepository: Decodable, Identifiable {
    let id: Int
    let name: String
    let full_name: String
    let isPrivate: Bool
    enum CodingKeys: String, CodingKey {
        case id, name, full_name
        case isPrivate = "private"
    }
}
private struct GHWorkflowList: Decodable { let workflows: [GHWorkflow] }
private struct GHWorkflow: Decodable, Identifiable {
    let id: Int
    let name: String
    let path: String
    let state: String
}
private struct GHWorkflowRuns: Decodable { let workflow_runs: [GHWorkflowRun] }
private struct GHWorkflowRun: Decodable, Identifiable {
    let id: Int
    let name: String
    let run_number: Int
    let status: String
    let conclusion: String?
    let html_url: String
    let event: String
    let created_at: String
    let updated_at: String
}

private enum GHError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let value) = self { return value }
        return "حدث خطأ غير معروف."
    }
}

private enum GHKeychain {
    static func save(_ token: GHStoredToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.tmoath07.inrpf.github",
            kSecAttrAccount as String: "oauth-token",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
    static func load() -> GHStoredToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.tmoath07.inrpf.github",
            kSecAttrAccount as String: "oauth-token",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(GHStoredToken.self, from: data)
    }
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.tmoath07.inrpf.github",
            kSecAttrAccount as String: "oauth-token"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
private final class GitHubIntegrationClient: ObservableObject {
    @Published var isAuthorized = false
    @Published var username = ""
    @Published var userCode = ""
    @Published var verificationURL = URL(string: "https://github.com/login/device")
    @Published var repositories: [GHRepository] = []
    @Published var workflows: [GHWorkflow] = []
    @Published var runs: [GHWorkflowRun] = []
    @Published var status = "اربط حساب GitHub للبدء."
    @Published var isBusy = false

    private let clientID = "Ov23liCTi2VzD4WSLM7C"
    private var token = GHKeychain.load()
    private var pollingTask: Task<Void, Never>?

    init() {
        // Never trust a persisted UI flag as proof of authentication.
        // Validate the Keychain token against GitHub before opening the workspace.
        isAuthorized = false
        if token != nil {
            status = "جارٍ التحقق من جلسة GitHub المحفوظة..."
            Task { await loadAccount() }
        }
    }

    func beginLogin() {
        guard !isBusy else { return }
        pollingTask?.cancel()
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                let device = try await requestDeviceCode()
                userCode = device.user_code
                verificationURL = URL(string: device.verification_uri)
                status = "افتح GitHub وأدخل الرمز. الرمز صالح لمدة 15 دقيقة."
                pollingTask = Task { await poll(device) }
            } catch {
                status = "تعذر بدء تسجيل الدخول: \(error.localizedDescription)"
            }
        }
    }

    private func requestDeviceCode() async throws -> GHDeviceCode {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(["client_id": clientID, "scope": "repo offline_access"])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        return try JSONDecoder().decode(GHDeviceCode.self, from: data)
    }

    private func poll(_ device: GHDeviceCode) async {
        let deadline = Date().addingTimeInterval(TimeInterval(device.expires_in))
        var interval = max(5, device.interval)
        while !Task.isCancelled && Date() < deadline {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                if Task.isCancelled { return }
                var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = formBody([
                    "client_id": clientID,
                    "device_code": device.device_code,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ])
                let (data, response) = try await URLSession.shared.data(for: request)
                try check(response, data)
                let result = try JSONDecoder().decode(GHTokenResponse.self, from: data)
                if let access = result.access_token {
                    let now = Date()
                    token = GHStoredToken(
                        accessToken: access,
                        refreshToken: result.refresh_token,
                        expiresAt: result.expires_in.map { now.addingTimeInterval(TimeInterval($0)) }
                    )
                    if let token { GHKeychain.save(token) }
                    userCode = ""
                    isAuthorized = true
                    status = "تم ربط GitHub. جارٍ تحميل الحساب..."
                    await loadAccount()
                    return
                }
                switch result.error ?? "" {
                case "authorization_pending":
                    status = "بانتظار موافقتك في GitHub..."
                case "slow_down":
                    interval += 5
                    status = "GitHub طلب إبطاء التحقق؛ المحاولة التالية بعد \(interval) ثوانٍ."
                case "expired_token":
                    userCode = ""
                    status = "انتهت صلاحية الرمز. ابدأ تسجيل الدخول من جديد."
                    return
                case "access_denied":
                    userCode = ""
                    status = "تم رفض تسجيل الدخول."
                    return
                default:
                    if let message = result.error_description {
                        userCode = ""
                        status = "فشل تسجيل الدخول: \(message)"
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                status = "مشكلة اتصال: \(error.localizedDescription)"
                return
            }
        }
        if !Task.isCancelled {
            userCode = ""
            status = "انتهت مدة الرمز. ابدأ تسجيل الدخول من جديد."
        }
    }

    func cancelLogin() {
        pollingTask?.cancel()
        pollingTask = nil
        userCode = ""
        status = "تم إلغاء تسجيل الدخول."
    }

    func signOut() {
        pollingTask?.cancel()
        GHKeychain.delete()
        token = nil
        isAuthorized = false
        username = ""
        repositories = []
        workflows = []
        runs = []
        userCode = ""
        status = "تم تسجيل الخروج."
    }

    func loadAccount() async {
        do {
            let user: GHUser = try await api("/user")
            username = user.login
            isAuthorized = true
            status = "متصل بحساب @\(user.login)"
            await loadRepositories()
        } catch {
            isAuthorized = false
            status = "تعذر التحقق من الحساب: \(error.localizedDescription)"
        }
    }

    func loadRepositories() async {
        do {
            repositories = try await api("/user/repos?sort=updated&per_page=100")
            status = "تم تحميل \(repositories.count) مستودع."
        } catch {
            status = "تعذر تحميل المستودعات: \(error.localizedDescription)"
        }
    }

    func createRepository(name: String, isPrivate: Bool) async throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GHError.message("اكتب اسم المستودع.") }
        let _: GHRepository = try await api("/user/repos", method: "POST", body: [
            "name": name, "private": isPrivate, "auto_init": true,
            "description": "Mod workspace managed by INRPF"
        ])
        await loadRepositories()
        status = "تم إنشاء المستودع \(name)."
    }

    func uploadFile(_ url: URL, to repository: GHRepository, repositoryPath: String) async throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 && size <= 90 * 1024 * 1024 else {
            throw GHError.message("الملف فارغ أو يتجاوز حد الرفع المباشر 90MB: \(url.lastPathComponent)")
        }
        let data = try Data(contentsOf: url)
        let pathCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encodedPath = repositoryPath.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: pathCharacters) ?? String($0)
        }.joined(separator: "/")
        let _: GHContentResult = try await api(
            "/repos/\(repository.full_name)/contents/\(encodedPath)",
            method: "PUT",
            body: ["message": "INRPF: upload \(url.lastPathComponent)", "content": data.base64EncodedString()]
        )
        status = "تم رفع \(url.lastPathComponent)."
    }

    func uploadItems(_ urls: [URL], to repository: GHRepository, inputFolder: String) async throws {
        guard !urls.isEmpty else { throw GHError.message("اختر ملفات التحويل أولاً.") }
        var files: [(URL, String)] = []
        let fm = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                throw GHError.message("الملف غير موجود: \(url.lastPathComponent)")
            }
            if isDirectory.boolValue {
                guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else {
                    throw GHError.message("تعذر قراءة المجلد: \(url.lastPathComponent)")
                }
                for case let child as URL in enumerator {
                    let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                    guard values.isRegularFile == true else { continue }
                    let relative = String(child.path.dropFirst(url.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    files.append((child, url.lastPathComponent + "/" + relative))
                }
            } else {
                files.append((url, url.lastPathComponent))
            }
        }
        guard !files.isEmpty else { throw GHError.message("المجلد المختار لا يحتوي ملفات.") }
        for (index, item) in files.enumerated() {
            try await uploadFile(item.0, to: repository, repositoryPath: "\(inputFolder)/\(item.1)")
            status = "رفع الملفات: \(index + 1) من \(files.count)"
        }
        status = "اكتمل رفع \(files.count) ملفاً إلى \(repository.full_name)/\(inputFolder)."
    }

    func loadWorkflows(for repository: GHRepository) async {
        do {
            let response: GHWorkflowList = try await api("/repos/\(repository.full_name)/actions/workflows?per_page=100")
            workflows = response.workflows.filter {
                $0.state == "active" && $0.path.hasSuffix("convert-pc-to-ps4.yml")
            }
            status = workflows.isEmpty
                ? "لم أجد Workflow التحويل convert-pc-to-ps4.yml في هذا المستودع."
                : "تم العثور على Workflow التحويل الصحيح."
        } catch {
            workflows = []
            status = "تعذر قراءة Workflows: \(error.localizedDescription)"
        }
    }

    func loadRuns(for repository: GHRepository) async {
        do {
            let response: GHWorkflowRuns = try await api("/repos/\(repository.full_name)/actions/runs?per_page=8")
            runs = response.workflow_runs
        } catch {
            status = "تعذر تحميل سجل GitHub Actions: \(error.localizedDescription)"
        }
    }

    func dispatch(_ workflow: GHWorkflow, repository: GHRepository, ref: String, inputs: [String: String]) async throws {
        let ref = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { throw GHError.message("اكتب اسم الفرع، مثل main.") }
        try await apiNoContent(
            "/repos/\(repository.full_name)/actions/workflows/\(workflow.id)/dispatches",
            body: ["ref": ref, "inputs": inputs]
        )
        status = "تم إرسال طلب تشغيل \(workflow.name) على \(ref)."
    }

    private func api<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        try await refreshIfNeeded()
        guard let access = token?.accessToken else { throw GHError.message("سجّل الدخول أولاً.") }
        var request = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func apiNoContent(_ path: String, body: [String: Any]) async throws {
        try await refreshIfNeeded()
        guard let access = token?.accessToken else { throw GHError.message("سجّل الدخول أولاً.") }
        var request = URLRequest(url: URL(string: "https://api.github.com" + path)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
    }

    private func refreshIfNeeded() async throws {
        guard var current = token, let expiry = current.expiresAt,
              expiry <= Date().addingTimeInterval(120) else { return }
        guard let refresh = current.refreshToken else {
            signOut()
            throw GHError.message("انتهت الجلسة. سجّل الدخول مجدداً.")
        }
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": clientID, "grant_type": "refresh_token", "refresh_token": refresh
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        let result = try JSONDecoder().decode(GHTokenResponse.self, from: data)
        guard let access = result.access_token else {
            signOut()
            throw GHError.message(result.error_description ?? "تعذّر تحديث جلسة GitHub.")
        }
        let now = Date()
        current.accessToken = access
        current.refreshToken = result.refresh_token ?? refresh
        current.expiresAt = result.expires_in.map { now.addingTimeInterval(TimeInterval($0)) }
        token = current
        GHKeychain.save(current)
    }

    private func formBody(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let fields = values.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return Data(fields.utf8)
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw GHError.message("استجابة شبكة غير معروفة.") }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw GHError.message(message ?? "GitHub API HTTP \(http.statusCode)")
        }
    }
}

private struct GHContentResult: Decodable {
    let content: GHContent?
}
private struct GHContent: Decodable { let name: String? }

private struct CameraCapturePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCapturePicker
        init(_ parent: CameraCapturePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.onDismiss()
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onDismiss()
            picker.dismiss(animated: true)
        }
    }
}

struct GitHubIntegrationView: View {
    private enum ActiveSheet: String, Identifiable, Equatable {
        case camera, files, folder
        var id: String { rawValue }
    }

    @StateObject private var client = GitHubIntegrationClient()
    @AppStorage("gta_github_authenticated") private var githubAuthenticated = false
    @State private var didConfirmGitHubSession = false
    @State private var repositoryName = ""
    @State private var isPrivate = true
    @State private var selectedRepositoryID: Int?
    @State private var selectedWorkflowID: Int?
    @State private var branchName = "main"
    @State private var activeSheet: ActiveSheet?
    @State private var selectedFileURLs: [URL] = []
    @State private var appFiles: [URL] = []
    @State private var monitorRefreshToken = 0
    @State private var autoDetectedMode: String?
    @State private var isDetectingFileTypes = false
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var cameraImage: UIImage?
    @State private var isDropTargeted = false
    @State private var inputFolder = "uploads/inrpf-input"
    @State private var conversionMode = "أوتو"
    @State private var toolkitZip = "tools-source/ZokiiStudio-Toolkit-FIXED.zip"
    @State private var releaseTag = ""
    @State private var vehicleSpawnName = "buccaneer2"

    private var selectedRepository: GHRepository? {
        client.repositories.first { $0.id == selectedRepositoryID }
    }
    private var selectedWorkflow: GHWorkflow? {
        client.workflows.first { $0.id == selectedWorkflowID }
    }

    private var resolvedConversionMode: String {
        guard conversionMode == "أوتو" else { return conversionMode }
        if let autoDetectedMode { return autoDetectedMode }
        let extensions = Set(selectedFileURLs.map { $0.pathExtension.lowercased() })
        if extensions.contains("rpf") { return "تحويل DLC الكمبيوتر إلى DLC السوني" }
        if extensions.contains("yft") || extensions.contains("ytd") {
            return "تحويل YFT وYTD وبناء DLC متعدد السيارات للسوني"
        }
        if selectedFileURLs.contains(where: isFiveMResourceFolder) {
            return "تحويل مود FiveM متعدد السيارات إلى DLC للسوني"
        }
        if !extensions.isDisjoint(with: ["zip", "rar", "7z"]) {
            return "تحويل ملفات PC إلى PS4"
        }
        return "تحويل الملفات وبناء RPF"
    }

    private var autoDetectionSummary: String {
        guard !selectedFileURLs.isEmpty else { return "أضف ملفاتك، وراح يحدد INRPF نوعها تلقائياً." }
        if isDetectingFileTypes { return "جاري فحص محتويات الملفات والأرشيفات..." }
        let names = selectedFileURLs.map { $0.pathExtension.isEmpty ? "مجلد" : $0.pathExtension.uppercased() }
        return "تم التعرف على: \(Array(Set(names)).sorted().joined(separator: "، ")) — الإجراء: \(resolvedConversionMode)"
    }

    private func updateAutoDetection(for urls: [URL]) async {
        guard conversionMode == "أوتو" else { return }
        guard !urls.isEmpty else {
            autoDetectedMode = nil
            isDetectingFileTypes = false
            return
        }
        isDetectingFileTypes = true
        defer { isDetectingFileTypes = false }
        var paths: [String] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    for case let child as URL in enumerator {
                        if (try? child.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                            paths.append(String(child.path.dropFirst(url.path.count)).lowercased())
                        }
                        if paths.count >= 20_000 { break }
                    }
                }
            } else if ["zip", "rar", "7z", "tar", "gz"].contains(url.pathExtension.lowercased()) {
                do {
                    let reader = try await ArchiveReader(reading: .fileURL(url))
                    var inspected = 0
                    while let entry = try await reader.nextEntry(), inspected < 20_000 {
                        paths.append(entry.path.lowercased())
                        inspected += 1
                    }
                } catch {
                    paths.append(url.lastPathComponent.lowercased())
                }
            } else {
                paths.append(url.lastPathComponent.lowercased())
            }
        }
        let joined = paths.joined(separator: "\n")
        if joined.contains("stream/") && joined.contains("data/") && joined.contains(".yft") && joined.contains(".meta") {
            autoDetectedMode = "تحويل مود FiveM متعدد السيارات إلى DLC للسوني"
        } else if paths.contains(where: { $0.hasSuffix(".rpf") }) {
            autoDetectedMode = "تحويل DLC الكمبيوتر إلى DLC السوني"
        } else if paths.contains(where: { $0.hasSuffix(".yft") || $0.hasSuffix(".ytd") }) {
            autoDetectedMode = "تحويل YFT وYTD وبناء DLC متعدد السيارات للسوني"
        } else if paths.contains(where: { [".zip", ".rar", ".7z"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) {
            autoDetectedMode = "تحويل ملفات PC إلى PS4"
        } else {
            autoDetectedMode = "تحويل الملفات وبناء RPF"
        }
    }

    private func isFiveMResourceFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        let stream = url.appendingPathComponent("stream", isDirectory: true)
        let data = url.appendingPathComponent("data", isDirectory: true)
        var streamIsDirectory: ObjCBool = false
        var dataIsDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: stream.path, isDirectory: &streamIsDirectory)
            && streamIsDirectory.boolValue
            && FileManager.default.fileExists(atPath: data.path, isDirectory: &dataIsDirectory)
            && dataIsDirectory.boolValue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !client.userCode.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("رمز التحقق").font(.headline)
                        Text(client.userCode)
                            .font(.system(size: 30, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        HStack {
                            Button("نسخ الرمز") { UIPasteboard.general.string = client.userCode }
                            Spacer()
                            if let url = client.verificationURL { Link("فتح GitHub", destination: url) }
                        }
                        Button("إلغاء تسجيل الدخول", role: .cancel) { client.cancelLogin() }
                    }
                    .padding(16).background(Color(red: 0.075, green: 0.085, blue: 0.13).opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
                }
                if client.isAuthorized {
                    repositorySection
                    uploadSection
                    workflowSection
                }
                Text(client.status)
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                LinearGradient(colors: [Color(red: 0.025, green: 0.035, blue: 0.065), Color(red: 0.055, green: 0.035, blue: 0.10), Color.black],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(red: 0.30, green: 0.22, blue: 0.75).opacity(0.16)).frame(width: 320).blur(radius: 90).offset(x: 170, y: -310)
            }.ignoresSafeArea()
        }
        .navigationTitle(client.isAuthorized ? "INRPF • GitHub" : "INRPF")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear {
            if client.isAuthorized {
                didConfirmGitHubSession = true
                githubAuthenticated = true
            }
        }
        .onChange(of: client.isAuthorized) { _, authorized in
            if authorized {
                didConfirmGitHubSession = true
                githubAuthenticated = true
            } else if didConfirmGitHubSession {
                githubAuthenticated = false
            }
        }
        .task(id: "\(selectedRepositoryID ?? 0)-\(monitorRefreshToken)") {
            guard let repository = selectedRepository else { return }
            while !Task.isCancelled {
                await client.loadRuns(for: repository)
                let isRunning = client.runs.contains { $0.status == "queued" || $0.status == "in_progress" || $0.status == "waiting" }
                guard isRunning else { break }
                try? await Task.sleep(for: .seconds(12))
            }
        }
        .onChange(of: selectedFileURLs) { _, urls in
            Task { await updateAutoDetection(for: urls) }
        }
        .onChange(of: conversionMode) { _, mode in
            if mode == "أوتو" {
                Task { await updateAutoDetection(for: selectedFileURLs) }
            }
        }
        .onChange(of: photoSelections) { _, items in
            Task { await importPhotos(items) }
        }
        .onChange(of: cameraImage) { _, image in
            guard let image, let data = image.jpegData(compressionQuality: 0.92) else { return }
            do {
                let url = try saveImportedData(data, name: "camera-\(UUID().uuidString).jpg")
                selectedFileURLs.append(url)
                client.status = "تمت إضافة صورة الكاميرا إلى قائمة الرفع."
            } catch { client.status = error.localizedDescription }
            cameraImage = nil
            activeSheet = nil
        }
        .sheet(isPresented: Binding(
            get: { activeSheet == .camera },
            set: { if !$0 && activeSheet == .camera { activeSheet = nil } }
        )) {
            CameraCapturePicker(image: $cameraImage, onDismiss: { activeSheet = nil })
                .ignoresSafeArea()
        }
        .inrpfDocumentPicker(
            isPresented: Binding(
                get: { activeSheet == .files },
                set: { if !$0 && activeSheet == .files { activeSheet = nil } }
            ),
            contentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: {
                activeSheet = nil
                importGitHubItems($0, itemDescription: "ملف")
            },
            onCancellation: {
                activeSheet = nil
                client.status = "تم إلغاء اختيار الملفات."
            }
        )
        .inrpfDocumentPicker(
            isPresented: Binding(
                get: { activeSheet == .folder },
                set: { if !$0 && activeSheet == .folder { activeSheet = nil } }
            ),
            contentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: {
                activeSheet = nil
                importGitHubItems($0, itemDescription: "مجلد")
            },
            onCancellation: {
                activeSheet = nil
                client.status = "تم إلغاء اختيار المجلد."
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.19), Color.white.opacity(0.055)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 62, height: 62)
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("INRPF").font(.system(size: 27, weight: .black, design: .rounded))
                        .tracking(0.4).foregroundStyle(.white)
                    Text("GITHUB CONNECTED WORKSPACE")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(1.25).foregroundStyle(Color.white.opacity(0.52))
                }
                Spacer(minLength: 0)
            }

            if client.isAuthorized {
                VStack(alignment: .leading, spacing: 8) {
                    Label("الحساب متصل", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(.green)
                    Text("@\(client.username)")
                        .font(.title3.bold()).foregroundStyle(.white)
                    Text("مستودعاتك وملفاتك وعمليات التحويل مرتبطة بحساب GitHub.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.68))
                    HStack(spacing: 10) {
                        Button {
                            Task { await client.loadRepositories() }
                        } label: {
                            Label("تحديث المستودعات", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button("تسجيل الخروج", role: .destructive) {
                            client.signOut()
                        }.buttonStyle(.bordered)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("كل شغلك يبدأ من GitHub")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("سجّل دخولك عشان تربط مستودعاتك، تنشئ مساحة لموداتك، وترفع الملفات وتشغّل GitHub Actions من داخل INRPF.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.70))
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        client.beginLogin()
                    } label: {
                        HStack(spacing: 10) {
                            if client.isBusy { ProgressView().tint(.black) }
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.headline)
                            Text(client.isBusy ? "جاري الاتصال بـ GitHub..." : "تسجيل الدخول باستخدام GitHub")
                                .font(.headline.bold())
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain).disabled(client.isBusy)

                    HStack(spacing: 5) {
                        Text("ما عندك حساب؟").foregroundStyle(.white.opacity(0.58))
                        Link("إنشاء حساب GitHub", destination: URL(string: "https://github.com/signup")!)
                            .fontWeight(.semibold).foregroundStyle(Color(red: 0.55, green: 0.72, blue: 1))
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 3)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                        Text("تتم المصادقة عبر GitHub Device Flow، ويحفظ رمز الجلسة في Keychain.")
                            .font(.caption2).foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 5)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.28), Color(red: 0.055, green: 0.055, blue: 0.075)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.11)))
    }

    private var repositorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("المستودعات").font(.headline)
            if client.repositories.isEmpty {
                Text("لا توجد مستودعات محمّلة حالياً.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(client.repositories) { repository in
                Button {
                    selectedRepositoryID = repository.id
                    selectedWorkflowID = nil
                    client.workflows = []
                    client.runs = []
                    Task {
                        await client.loadWorkflows(for: repository)
                        await client.loadRuns(for: repository)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(repository.full_name).font(.subheadline.bold())
                            Text(repository.isPrivate ? "خاص" : "عام").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedRepositoryID == repository.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .padding(11)
                    .background(selectedRepositoryID == repository.id ? Color.purple.opacity(0.22) : Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            Divider()
            Text("إنشاء مستودع جديد").font(.subheadline.bold())
            TextField("اسم المستودع", text: $repositoryName)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
            Toggle("مستودع خاص", isOn: $isPrivate)
            Button("إنشاء المستودع") {
                Task {
                    do {
                        try await client.createRepository(name: repositoryName, isPrivate: isPrivate)
                        repositoryName = ""
                    } catch { client.status = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(repositoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16).background(Color(red: 0.075, green: 0.085, blue: 0.13).opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
    }

    private var uploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("رفع ملف مود إلى المستودع").font(.headline)
            Text(selectedRepository?.full_name ?? "اختر مستودعاً أولاً")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("اختيار ملفات") {
                    client.status = "اختر الملفات المراد رفعها من تطبيق «الملفات»."
                    activeSheet = .files
                }
                .buttonStyle(.bordered)
                Button("اختيار مجلد") {
                    client.status = "اختر مجلد المود من تطبيق «الملفات»."
                    activeSheet = .folder
                }
                .buttonStyle(.bordered)
            }
            HStack {
                PhotosPicker(selection: $photoSelections, maxSelectionCount: 20, matching: .images) {
                    Label("مكتبة الصور", systemImage: "photo.on.rectangle")
                }.buttonStyle(.bordered)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { activeSheet = .camera } label: {
                        Label("الكاميرا", systemImage: "camera")
                    }.buttonStyle(.bordered)
                }
            }
            Text("عدد العناصر المحددة: \(selectedFileURLs.count)").font(.caption).foregroundStyle(.secondary)
            ForEach(selectedFileURLs, id: \.path) { file in
                Label(file.lastPathComponent, systemImage: "doc.fill").font(.caption).lineLimit(1)
            }
            TextField("مجلد الإدخال في المستودع", text: $inputFolder)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
            Button("تحديث متصفح ملفات INRPF") { refreshAppFiles() }.buttonStyle(.bordered)
            ForEach(appFiles.prefix(30), id: \.path) { file in
                Button {
                    if !selectedFileURLs.contains(file) { selectedFileURLs.append(file) }
                } label: {
                    Label(file.lastPathComponent, systemImage: "folder.badge.plus").font(.caption).lineLimit(1)
                }.buttonStyle(.plain)
            }
            Button("رفع جميع الملفات إلى GitHub") {
                guard let repository = selectedRepository else { return }
                let urls = selectedFileURLs
                let folder = inputFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                guard !folder.isEmpty else { client.status = "اكتب مجلد الإدخال."; return }
                Task {
                    do {
                        try await client.uploadItems(urls, to: repository, inputFolder: folder)
                    } catch { client.status = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedRepository == nil || selectedFileURLs.isEmpty)
            Text("يدعم اختيار الملفات والمجلدات من «الملفات»، والسحب والإفلات، والصور والكاميرا. تظهر المجلدات الداخلية ضمن المتصفح.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(isDropTargeted ? Color.purple.opacity(0.22) : Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let source: URL?
                    if let value = item as? URL { source = value }
                    else if let data = item as? Data { source = URL(dataRepresentation: data, relativeTo: nil) }
                    else if let value = item as? String { source = URL(string: value) }
                    else { source = nil }
                    guard let source, source.isFileURL,
                          let copied = try? FileImportService.importItem(from: source, category: "GitHubUploads") else { return }
                    DispatchQueue.main.async {
                        if !selectedFileURLs.contains(copied) { selectedFileURLs.append(copied) }
                        client.status = "تمت إضافة الملف المسحوب إلى قائمة الرفع."
                    }
                }
            }
            return !providers.isEmpty
        }

    }


    private func importGitHubItems(_ result: Result<[URL], Error>, itemDescription: String) {
        activeSheet = nil
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else {
                client.status = "لم يتم اختيار أي عنصر."
                return
            }
            client.status = "تم اختيار العناصر. جاري نسخها بأمان إلى مساحة INRPF..."
            Task {
                do {
                    let imported = try await Task.detached(priority: .userInitiated) {
                        try urls.map {
                            try FileImportService.importItem(from: $0, category: "GitHubUploads")
                        }
                    }.value
                    selectedFileURLs.append(contentsOf: imported)
                    client.status = "تم نسخ \(imported.count) \(itemDescription) إلى قائمة الرفع."
                } catch {
                    client.status = "تعذر نسخ العناصر: \(error.localizedDescription)"
                }
            }
        case .failure(let error):
            client.status = "تعذر استيراد العناصر: \(error.localizedDescription)"
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            do {
                let url = try saveImportedData(data, name: "photo-\(UUID().uuidString).\(ext)")
                selectedFileURLs.append(url)
            } catch { client.status = error.localizedDescription }
        }
        photoSelections = []
        if !selectedFileURLs.isEmpty { client.status = "تمت إضافة الصور إلى قائمة الرفع." }
    }

    private func saveImportedData(_ data: Data, name: String) throws -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTA Converter/GitHubUploads", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func refreshAppFiles() {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTA Converter", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            appFiles = []
            return
        }
        appFiles = enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true || values.isDirectory == true else { return nil }
            return url
        }.sorted { lhs, rhs in
            let leftDirectory = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            let rightDirectory = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if leftDirectory != rightDirectory { return leftDirectory }
            return lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
        }
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("GitHub Actions").font(.headline)
                    Text("متابعة عمليات التحويل وحالتها مباشرة").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    guard let repository = selectedRepository else { return }
                    Task { await client.loadRuns(for: repository) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.headline).padding(9)
                        .background(Color.white.opacity(0.08), in: Circle())
                }.disabled(selectedRepository == nil)
            }
            if client.workflows.isEmpty {
                Text("لا توجد Workflows مفعّلة لهذا المستودع.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(client.workflows) { workflow in
                Button { selectedWorkflowID = workflow.id } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(workflow.name).font(.subheadline.bold())
                            Text(workflow.path).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedWorkflowID == workflow.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .padding(10)
                    .background(selectedWorkflowID == workflow.id ? Color.purple.opacity(0.22) : Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            }
            if !client.runs.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("آخر عمليات التشغيل").font(.subheadline.bold())
                    ForEach(client.runs) { run in
                        Link(destination: URL(string: run.html_url) ?? URL(string: "https://github.com")!) {
                            HStack(spacing: 10) {
                                Image(systemName: run.status == "completed"
                                      ? (run.conclusion == "success" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                      : "arrow.triangle.2.circlepath")
                                    .foregroundStyle(run.status == "completed"
                                                     ? (run.conclusion == "success" ? .green : .red)
                                                     : .orange)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(run.name) • #\(run.run_number)").font(.caption.bold()).foregroundStyle(.white)
                                    Text(run.status == "completed" ? "مكتمل: \(run.conclusion ?? "غير محدد")" : "قيد التنفيذ: \(run.status)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            } else {
                Text("ما فيه عمليات تشغيل ظاهرة حالياً.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("نوع التحويل", selection: $conversionMode) {
                ForEach(["أوتو", "فحص الأدوات", "تحويل ملفات PC إلى PS4", "تحويل سيارة إلى DLC للسوني", "تحويل الملفات وبناء RPF", "تحويل DLC الكمبيوتر إلى DLC السوني", "تحويل مود FiveM متعدد السيارات إلى DLC للسوني", "تحويل YFT وYTD وبناء DLC متعدد السيارات للسوني", "استخراج الصور من YTD", "فك ملفات RPF", "بناء ملف RPF"], id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            if conversionMode == "أوتو" {
                Label(autoDetectionSummary, systemImage: "sparkles")
                    .font(.caption).foregroundStyle(Color(red: 0.65, green: 0.78, blue: 1))
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField("اسم الفرع", text: $branchName)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
            TextField("مسار ZIP الأدوات", text: $toolkitZip)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
            TextField("Release Tag (اتركه فارغاً عند رفع ملفاتك)", text: $releaseTag)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
            TextField("اسم Spawn للسيارة", text: $vehicleSpawnName)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
            Button("رفع الملفات ثم تشغيل Workflow") {
                guard let repository = selectedRepository, let workflow = selectedWorkflow else { return }
                let urls = selectedFileURLs
                let baseFolder = inputFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                guard !baseFolder.isEmpty,
                      !baseFolder.split(separator: "/").contains(".."),
                      !baseFolder.split(separator: "/").contains(".") else {
                    client.status = "مسار مجلد الإدخال غير صالح."
                    return
                }
                let folder = "\(baseFolder)/inrpf-\(UUID().uuidString.lowercased())"
                Task {
                    do {
                        guard !urls.isEmpty else {
                            throw GHError.message("اختر ملفات التحويل قبل تشغيل Workflow.")
                        }
                        try await client.uploadItems(urls, to: repository, inputFolder: folder)
                        try await client.dispatch(workflow, repository: repository, ref: branchName, inputs: [
                            "mode": resolvedConversionMode,
                            "toolkit_zip": toolkitZip,
                            "release_tag": releaseTag,
                            "url": "",
                            "input_folder": folder,
                            "vehicle_spawn_name": vehicleSpawnName
                        ])
                        selectedFileURLs = []
                        monitorRefreshToken += 1
                        client.status = "تم رفع الملفات وتشغيل Workflow. مجلد الإدخال: \(folder)"
                    } catch { client.status = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent).disabled(selectedWorkflow == nil || selectedRepository == nil || selectedFileURLs.isEmpty)
        }
        .padding(16).background(Color(red: 0.075, green: 0.085, blue: 0.13).opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.075), lineWidth: 1))
    }
}