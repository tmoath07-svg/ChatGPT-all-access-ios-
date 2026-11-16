import Foundation
import Security

enum INRPFReportClientError: LocalizedError {
    case missingToken
    case invalidResponse
    case rejected(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingToken: return "أدخل رمز التقارير واحفظه أولاً."
        case .invalidResponse: return "استجابة السيرفر غير مفهومة."
        case let .rejected(code, message): return "رفض السيرفر التقرير (HTTP \(code)): \(message)"
        }
    }
}

enum INRPFReportClient {
    private static let service = "com.tmoath07.inrpf.report-token"
    private static let account = "INRPF_REPORT_TOKEN"
    private static let endpoint = URL(string: "https://inrpf-server.onrender.com/api/reports")!

    static func saveToken(_ token: String) throws {
        let data = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard !data.isEmpty else { throw INRPFReportClientError.missingToken }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func hasSavedToken() -> Bool {
        (try? loadToken()) != nil
    }

    private static func loadToken() throws -> String {
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
              let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw INRPFReportClientError.missingToken
        }
        return token
    }

    struct ReceivedReport: Decodable, Identifiable {
        let received_at: String
        let report_id: String
        let app_version: String
        let build_number: String
        let passed_count: Int
        let failed_count: Int
        let all_passed: Bool
        var id: String { report_id.isEmpty ? received_at : report_id }
    }

    static func fetchReports() async throws -> [ReceivedReport] {
        let token = try loadToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw INRPFReportClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "تعذر جلب التقارير"
            throw INRPFReportClientError.rejected(http.statusCode, message)
        }
        struct Envelope: Decodable { let reports: [ReceivedReport] }
        return try JSONDecoder().decode(Envelope.self, from: data).reports
    }

    static func send(report: INRPFDeviceTestReport) async throws {
        let token = try loadToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formatter = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "report_id": UUID().uuidString,
            "generated_at": formatter.string(from: report.generatedAt),
            "app_version": report.appVersion,
            "build_number": report.buildNumber,
            "platform": report.platform,
            "device_model": report.deviceModel,
            "passed_count": report.passedCount,
            "failed_count": report.failedCount,
            "all_passed": report.allPassed,
            "results": report.results.map {
                ["id": $0.id, "title": $0.title, "passed": $0.passed, "details": $0.details] as [String: Any]
            }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw INRPFReportClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "تعذر قبول التقرير"
            throw INRPFReportClientError.rejected(http.statusCode, message)
        }
    }
}
