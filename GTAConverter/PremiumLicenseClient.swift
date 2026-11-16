import Foundation
import SwiftUI
import Security

@MainActor
final class INRPFPremiumLicenseClient: ObservableObject {
    @Published var code = ""
    @Published private(set) var hasGitHubTools = false
    @Published private(set) var isChecking = true
    @Published var status = "جارٍ التحقق من ترخيص INRPF Premium..."

    private static let endpoint = URL(string: "https://inrpf-server.onrender.com")!
    private static let keychainService = "com.tmoath07.inrpf.premium"
    private static let keychainAccount = "github-tools-activation"

    init() { Task { await validateSavedActivation() } }

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
        let result = SecItemAdd(item as CFDictionary, nil)
        guard result == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
    }

    private func request(path: String, body: [String: String]? = nil, activation: String? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: Self.endpoint.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let activation {
            request.setValue("Bearer \(activation)", forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }

    func validateSavedActivation() async {
        isChecking = true
        defer { isChecking = false }
        guard let activation = loadActivation(), !activation.isEmpty else {
            hasGitHubTools = false
            status = "أدخل كود INRPF Premium لفتح أدوات GitHub."
            return
        }
        do {
            let (data, statusCode) = try await request(path: "api/license/validate", activation: activation)
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let features = payload?["features"] as? [String] ?? []
            hasGitHubTools = (200...299).contains(statusCode) && features.contains("github_tools")
            status = hasGitHubTools ? "ترخيص GitHub Premium فعّال." : "الترخيص غير فعّال. أدخل كوداً صالحاً."
        } catch {
            hasGitHubTools = false
            status = "تعذر التحقق من الترخيص عبر الإنترنت: \(error.localizedDescription)"
        }
    }

    func redeem() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { status = "اكتب كود التفعيل أولاً."; return }
        isChecking = true
        defer { isChecking = false }
        do {
            let (data, statusCode) = try await request(path: "api/license/redeem", body: ["code": trimmed])
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard (200...299).contains(statusCode),
                  let activation = payload?["activation_id"] as? String,
                  let features = payload?["features"] as? [String],
                  features.contains("github_tools") else {
                let error = payload?["error"] as? String ?? "invalid_license"
                status = error == "code_already_used" ? "هذا الكود مستخدم من قبل." : "تعذر تفعيل الكود: \(error)"
                return
            }
            try saveActivation(activation)
            hasGitHubTools = true
            code = ""
            status = "تم تفعيل أدوات GitHub بنجاح."
        } catch {
            hasGitHubTools = false
            status = "فشل الاتصال بخادم التراخيص: \(error.localizedDescription)"
        }
    }
}

struct INRPFPremiumLicenseGateView: View {
    @ObservedObject var client: INRPFPremiumLicenseClient
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill").font(.system(size: 48, weight: .semibold)).foregroundStyle(.purple)
            Text("INRPF Premium").font(.system(size: 27, weight: .bold, design: .rounded))
            Text("أدوات GitHub المتقدمة مقفلة. أدخل كود التفعيل لمرة واحدة لفتح مساحة GitHub.")
                .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
            TextField("INRPF-XXXX-XXXX-XXXX-XXXX", text: $client.code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.system(.body, design: .monospaced)).padding(14)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            Button { Task { await client.redeem() } } label: {
                HStack { if client.isChecking { ProgressView().tint(.white) }; Text("تفعيل الكود") }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .disabled(client.isChecking || client.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text(client.status).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("إعادة التحقق من الترخيص") { Task { await client.validateSavedActivation() } }
                .font(.caption).disabled(client.isChecking)
        }
        .padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea()).preferredColorScheme(.dark)
    }
}
