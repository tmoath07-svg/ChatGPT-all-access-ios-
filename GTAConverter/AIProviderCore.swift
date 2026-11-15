import Foundation
import Combine
import Security

struct AIProviderConfiguration: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var baseURL: String
    var modelID: String
    var updatedAt: Date

    init(id: String = UUID().uuidString, name: String, baseURL: String, modelID: String = "") {
        self.id = id
        self.name = name
        self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.modelID = modelID
        self.updatedAt = Date()
    }
}

enum AIProviderError: LocalizedError {
    case invalidBaseURL
    case missingAPIKey
    case invalidResponse
    case http(Int, String)
    case noModel
    case malformedPayload

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "عنوان Base URL غير صالح."
        case .missingAPIKey: return "أدخل API Key واحفظه أولاً."
        case .invalidResponse: return "استجابة مزود الذكاء الاصطناعي غير مفهومة."
        case .http(let code, let message): return "خطأ API (HTTP \(code)): \(message)"
        case .noModel: return "اختر Model ID قبل إرسال الرسالة."
        case .malformedPayload: return "استجابة النموذج لا تحتوي على بيانات قابلة للقراءة."
        }
    }
}

enum AISecretStore {
    private static let service = "com.tmoath07.inrpf.ai-provider"

    static func save(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func load(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw AIProviderError.missingAPIKey
        }
        return value
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class AIProviderStore: ObservableObject {
    @Published private(set) var providers: [AIProviderConfiguration] = []
    @Published var selectedProviderID: String?

    private let storageKey = "inrpf.ai.providers.v1"
    private let selectionKey = "inrpf.ai.selected-provider.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AIProviderConfiguration].self, from: data) {
            providers = decoded
        }
        selectedProviderID = UserDefaults.standard.string(forKey: selectionKey)
        if selectedProviderID == nil { selectedProviderID = providers.first?.id }
    }

    var selectedProvider: AIProviderConfiguration? {
        providers.first { $0.id == selectedProviderID }
    }

    func apiKey(for provider: AIProviderConfiguration) throws -> String {
        try AISecretStore.load(account: provider.id)
    }

    func save(name: String, baseURL: String, apiKey: String, modelID: String, editingID: String? = nil) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, let url = URL(string: cleanURL),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { throw AIProviderError.invalidBaseURL }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.missingAPIKey
        }

        if let editingID, let index = providers.firstIndex(where: { $0.id == editingID }) {
            var updated = providers[index]
            updated.name = cleanName
            updated.baseURL = cleanURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            updated.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.updatedAt = Date()
            try AISecretStore.save(apiKey, account: updated.id)
            providers[index] = updated
        } else {
            var created = AIProviderConfiguration(name: cleanName, baseURL: cleanURL, modelID: modelID)
            try AISecretStore.save(apiKey, account: created.id)
            providers.append(created)
            selectedProviderID = created.id
        }
        persist()
    }

    func select(_ id: String) {
        selectedProviderID = id
        UserDefaults.standard.set(id, forKey: selectionKey)
    }

    func selectModel(_ modelID: String, for providerID: String) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        providers[index].modelID = modelID
        providers[index].updatedAt = Date()
        persist()
    }

    func remove(_ provider: AIProviderConfiguration) {
        AISecretStore.delete(account: provider.id)
        providers.removeAll { $0.id == provider.id }
        if selectedProviderID == provider.id { selectedProviderID = providers.first?.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(selectedProviderID, forKey: selectionKey)
    }
}

enum AIProviderAPI {
    static func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        let request = try makeRequest(baseURL: baseURL, suffix: "models", apiKey: apiKey, method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIProviderError.invalidResponse
        }
        let candidates = (json["data"] as? [[String: Any]]) ?? (json["models"] as? [[String: Any]]) ?? []
        let values = candidates.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }
            .filter { !$0.isEmpty }
        return Array(Set(values)).sorted()
    }

    static func chat(baseURL: String, apiKey: String, modelID: String,
                     messages: [[String: Any]], tools: [[String: Any]]) async throws -> [String: Any] {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.noModel
        }
        var request = try makeRequest(baseURL: baseURL, suffix: "chat/completions", apiKey: apiKey, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = ["model": modelID, "messages": messages, "temperature": 0.2]
        if !tools.isEmpty {
            payload["tools"] = tools
            payload["tool_choice"] = "auto"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIProviderError.malformedPayload
        }
        return message
    }

    private static func makeRequest(baseURL: String, suffix: String, apiKey: String,
                                    method: String) throws -> URLRequest {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let base = URL(string: trimmed), let scheme = base.scheme,
              ["https", "http"].contains(scheme.lowercased()), base.host != nil else {
            throw AIProviderError.invalidBaseURL
        }
        let url = URL(string: trimmed + "/" + suffix)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let message = (body?["error"] as? [String: Any])?["message"] as? String
                ?? body?["message"] as? String ?? "لم يقدّم المزود تفاصيل إضافية."
            throw AIProviderError.http(http.statusCode, message)
        }
    }
}
