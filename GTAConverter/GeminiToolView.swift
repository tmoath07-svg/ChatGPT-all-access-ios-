import Foundation
import SwiftUI
import Security

@MainActor
final class GeminiLicenseClient: ObservableObject {
    @Published var code = ""
    @Published private(set) var hasAccess = false
    @Published private(set) var isChecking = true
    @Published var status = "جارٍ التحقق من صلاحية Gemini..."
    private(set) var activation = ""

    private static let endpoint = URL(string: "https://inrpf-server.onrender.com")!
    private static let keychainService = "com.tmoath07.inrpf.gemini"
    private static let keychainAccount = "gemini-tool-activation"

    init() {
        activation = loadActivation() ?? ""
        Task { await validateActivation() }
    }

    private func loadActivation() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveActivation(_ value: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func post(_ path: String, body: [String: Any]? = nil, token: String? = nil) async throws -> (Data, Int) {
        let url = path.split(separator: "/").reduce(Self.endpoint) { $0.appendingPathComponent(String($1)) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }

    func validateActivation() async {
        isChecking = true
        defer { isChecking = false }
        guard !activation.isEmpty else {
            hasAccess = false
            status = "أدخل كود Gemini لفتح الأداة."
            return
        }
        do {
            let (data, statusCode) = try await post("api/license/validate", token: activation)
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let features = payload?["features"] as? [String] ?? []
            hasAccess = (200...299).contains(statusCode) && features.contains("gemini_tool")
            status = hasAccess ? "تم التحقق — Gemini متاح." : "الكود غير فعّال أو لا يتضمن ميزة Gemini."
            if !hasAccess { activation = "" }
        } catch {
            hasAccess = false
            status = "تعذر التحقق من الترخيص: \(error.localizedDescription)"
        }
    }

    func redeem() async {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !value.isEmpty else { status = "اكتب كود التفعيل أولاً."; return }
        isChecking = true
        defer { isChecking = false }
        do {
            let (data, statusCode) = try await post("api/license/redeem", body: ["code": value])
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard (200...299).contains(statusCode),
                  let token = payload?["activation_id"] as? String,
                  let features = payload?["features"] as? [String],
                  features.contains("gemini_tool") else {
                status = "الكود غير صالح أو غير مخصص لأداة Gemini."
                return
            }
            try saveActivation(token)
            activation = token
            hasAccess = true
            code = ""
            status = "تم فتح أداة Gemini بنجاح."
        } catch {
            status = "تعذر تفعيل الكود: \(error.localizedDescription)"
        }
    }

    func get(_ path: String) async throws -> Data {
        guard hasAccess, !activation.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let url = path.split(separator: "/").reduce(Self.endpoint) { $0.appendingPathComponent(String($1)) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 40
        request.setValue("Bearer \(activation)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = payload?["error"] as? [String: Any]
            throw NSError(domain: "GeminiAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: error?["message"] as? String ?? "HTTP \(http.statusCode)"])
        }
        return data
    }

    func send(messages: [[String: String]], model: String) async throws -> String {
        guard hasAccess, !activation.isEmpty else { throw URLError(.userAuthenticationRequired) }
        let body: [String: Any] = ["model": model, "messages": messages, "temperature": 0.3]
        let (data, statusCode) = try await post("api/gemini/v1/chat/completions", body: body, token: activation)
        guard (200...299).contains(statusCode),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = payload["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let error = payload?["error"] as? [String: Any]
            throw NSError(domain: "GeminiAPI", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: error?["message"] as? String ?? "لم يصل رد صالح من Gemini."])
        }
        return text
    }
}

private struct GeminiChatMessage: Identifiable {
    let id = UUID()
    let role: String
    let text: String
}

struct GeminiToolView: View {
    @StateObject private var license = GeminiLicenseClient()
    @State private var messages: [GeminiChatMessage] = []
    @State private var input = ""
    @State private var model = "gemini-2.5-flash"
    @State private var models: [String] = ["gemini-2.5-flash"]
    @State private var isSending = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                GTAAppBackground()
                if license.hasAccess {
                    chatView
                } else {
                    licenseGate
                }
            }
            .navigationTitle("Gemini")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if license.hasAccess { await loadModels() }
            }
            .onChange(of: license.hasAccess) { _, enabled in
                if enabled { Task { await loadModels() } }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var licenseGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 52, weight: .semibold)).foregroundStyle(.purple)
            Text("Google Gemini").font(.title.bold()).foregroundStyle(.white)
            Text("هذه الأداة تحتاج كود تفعيل Gemini صادر من لوحة تحكم INRPF.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
            TextField("INRPF-XXXX-XXXX-XXXX-XXXX", text: $license.code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(.body, design: .monospaced)).padding(14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Button {
                Task { await license.redeem() }
            } label: {
                HStack { if license.isChecking { ProgressView().tint(.white) }; Text("فتح Gemini بالكود") }
                    .frame(maxWidth: .infinity).padding(13)
            }
            .buttonStyle(.borderedProminent).tint(.purple)
            .disabled(license.isChecking || license.code.trimmingCharacters(in: .whitespaces).isEmpty)
            Text(license.status).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.65))
            Button("إعادة التحقق") { Task { await license.validateActivation() } }
                .font(.caption).disabled(license.isChecking)
        }
        .padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatView: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Gemini", systemImage: "sparkles").font(.headline).foregroundStyle(.white)
                Spacer()
                Menu {
                    ForEach(models, id: \.self) { item in
                        Button(item) { model = item }
                    }
                } label: {
                    Label(model, systemImage: "chevron.down").font(.caption).lineLimit(1)
                }
            }
            .padding(.horizontal, 14).padding(.top, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        Text("اسأل Gemini عن ملفاتك أو البرمجة أو أي موضوع تحتاجه.")
                            .foregroundStyle(.white.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(message.role == "user" ? "أنت" : "Gemini")
                                .font(.caption.bold()).foregroundStyle(message.role == "user" ? .purple : .green)
                            Text(message.text).font(.body).foregroundStyle(.white).textSelection(.enabled)
                        }
                        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(message.role == "user" ? 0.10 : 0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                }
                .padding(14)
            }
            if !errorText.isEmpty {
                Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal, 14)
            }
            HStack(alignment: .bottom, spacing: 9) {
                TextField("اكتب رسالتك إلى Gemini...", text: $input, axis: .vertical)
                    .lineLimit(1...5).padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    Task { await sendMessage() }
                } label: {
                    if isSending { ProgressView().tint(.white).frame(width: 44, height: 44) }
                    else { Image(systemName: "paperplane.fill").frame(width: 44, height: 44) }
                }
                .buttonStyle(.borderedProminent).tint(.purple)
                .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        }
    }

    private func loadModels() async {
        do {
            let data = try await license.get("api/gemini/v1/models")
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let items = (payload?["data"] as? [[String: Any]] ?? [])
                .compactMap { $0["id"] as? String }
            if !items.isEmpty {
                models = items.sorted()
                if !models.contains(model) { model = models.first ?? "gemini-2.5-flash" }
            }
        } catch {
            errorText = "تعذر جلب النماذج: \(error.localizedDescription)"
        }
    }

    private func sendMessage() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        input = ""
        messages.append(GeminiChatMessage(role: "user", text: prompt))
        isSending = true
        errorText = ""
        defer { isSending = false }
        do {
            let history = messages.map { ["role": $0.role, "content": $0.text] }
            let reply = try await license.send(messages: history, model: model)
            messages.append(GeminiChatMessage(role: "assistant", text: reply))
        } catch {
            errorText = error.localizedDescription
        }
    }
}
