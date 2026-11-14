import SwiftUI
import UniformTypeIdentifiers
import Security
import UIKit

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
    @Published var status = "اربط حساب GitHub للبدء."
    @Published var isBusy = false

    private let clientID = "Ov23liCTi2VzD4WSLM7C"
    private var token = GHKeychain.load()
    private var pollingTask: Task<Void, Never>?

    init() {
        isAuthorized = token != nil
        if isAuthorized {
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
        request.httpBody = formBody([
            "client_id": clientID,
            "scope": "repo offline_access"
        ])
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

    func uploadFile(_ url: URL, to repository: GHRepository) async throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 && size <= 90 * 1024 * 1024 else {
            throw GHError.message("الملف فارغ أو يتجاوز حد الرفع المباشر 90MB.")
        }
        let data = try Data(contentsOf: url)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        let fileName = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: allowed) ?? "mod-upload.bin"
        let path = "uploads/" + fileName
        let _: GHContentResult = try await api(
            "/repos/\(repository.full_name)/contents/\(path)",
            method: "PUT",
            body: ["message": "INRPF: upload \(url.lastPathComponent)", "content": data.base64EncodedString()]
        )
        status = "تم رفع الملف إلى \(repository.full_name)/\(path)."
    }

    func loadWorkflows(for repository: GHRepository) async {
        do {
            let response: GHWorkflowList = try await api("/repos/\(repository.full_name)/actions/workflows?per_page=100")
            workflows = response.workflows.filter { $0.state == "active" }
            status = "تم تحميل \(workflows.count) Workflow."
        } catch {
            workflows = []
            status = "تعذر قراءة Workflows: \(error.localizedDescription)"
        }
    }

    func dispatch(_ workflow: GHWorkflow, repository: GHRepository, ref: String) async throws {
        let ref = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { throw GHError.message("اكتب اسم الفرع، مثل main.") }
        try await apiNoContent(
            "/repos/\(repository.full_name)/actions/workflows/\(workflow.id)/dispatches",
            body: ["ref": ref]
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

struct GitHubIntegrationView: View {
    @StateObject private var client = GitHubIntegrationClient()
    @State private var repositoryName = ""
    @State private var isPrivate = true
    @State private var selectedRepositoryID: Int?
    @State private var selectedWorkflowID: Int?
    @State private var branchName = "main"
    @State private var showingFileImporter = false
    @State private var selectedFileURL: URL?

    private var selectedRepository: GHRepository? {
        client.repositories.first { $0.id == selectedRepositoryID }
    }
    private var selectedWorkflow: GHWorkflow? {
        client.workflows.first { $0.id == selectedWorkflowID }
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
                    .padding(16).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))
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
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("GitHub")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): selectedFileURL = urls.first
            case .failure(let error): client.status = "تعذر اختيار الملف: \(error.localizedDescription)"
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("INRPF GitHub Integration", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline.bold())
            Text(client.isAuthorized ? "متصل: @\(client.username)" : "سجّل الدخول لربط مستودعات GitHub وتشغيل عمليات البناء.")
                .font(.subheadline).foregroundStyle(.secondary)
            if client.isAuthorized {
                Button("تحديث المستودعات") { Task { await client.loadRepositories() } }
                    .buttonStyle(.borderedProminent)
                Button("تسجيل الخروج", role: .destructive) { client.signOut() }
            } else {
                Button { client.beginLogin() } label: {
                    Label("تسجيل الدخول إلى GitHub", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(client.isBusy)
            }
        }
        .padding(16).background(Color.purple.opacity(0.16)).clipShape(RoundedRectangle(cornerRadius: 18))
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
                    Task { await client.loadWorkflows(for: repository) }
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
        .padding(16).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var uploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("رفع ملف مود إلى المستودع").font(.headline)
            Text(selectedRepository?.full_name ?? "اختر مستودعاً أولاً")
                .font(.caption).foregroundStyle(.secondary)
            Button("اختيار ملف من تطبيق الملفات") { showingFileImporter = true }
                .buttonStyle(.bordered)
            if let selectedFileURL {
                Text(selectedFileURL.lastPathComponent).font(.caption).lineLimit(1)
            }
            Button("رفع الملف إلى GitHub") {
                guard let repository = selectedRepository, let file = selectedFileURL else { return }
                Task {
                    do {
                        try await client.uploadFile(file, to: repository)
                        selectedFileURL = nil
                    } catch { client.status = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedRepository == nil || selectedFileURL == nil)
            Text("الحد الحالي للرفع المباشر 90MB للملف الواحد.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var workflowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Actions").font(.headline)
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
            TextField("اسم الفرع", text: $branchName)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never)
            Button("تشغيل Workflow المحدد") {
                guard let repository = selectedRepository, let workflow = selectedWorkflow else { return }
                Task {
                    do { try await client.dispatch(workflow, repository: repository, ref: branchName) }
                    catch { client.status = error.localizedDescription }
                }
            }
            .buttonStyle(.borderedProminent).disabled(selectedWorkflow == nil)
        }
        .padding(16).background(Color.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
