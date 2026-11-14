import SwiftUI
import Security

struct GitHubAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var accountName = ""
    @State private var status = "اربط حساب GitHub لتجهيز اتصال التطبيق."
    @State private var isBusy = false
    @State private var isConnected = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.035, green: 0.025, blue: 0.065).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Color.purple)
                            Text("تسجيل الدخول وربط GitHub")
                                .font(.title2.bold()).foregroundStyle(.white)
                            Text("ما نطلب كلمة مرور GitHub داخل التطبيق. الربط يتم برمز وصول شخصي تحفظه iOS داخل Keychain.")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        }

                        if isConnected {
                            Label("الحساب المرتبط: \(accountName)", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Button(role: .destructive, action: disconnect) {
                                Label("فصل الحساب وحذف الرمز المحفوظ", systemImage: "rectangle.portrait.and.arrow.right")
                                    .frame(maxWidth: .infinity).padding(13)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("رمز GitHub").font(.headline).foregroundStyle(.white)
                                SecureField("الصق Fine-grained Personal Access Token", text: $token)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textContentType(.password)
                                    .padding(14)
                                    .background(.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .foregroundStyle(.white)
                                Button(action: connect) {
                                    HStack {
                                        if isBusy { ProgressView().tint(.white) }
                                        Text(isBusy ? "جاري التحقق..." : "التحقق وربط الحساب")
                                    }
                                    .font(.headline).frame(maxWidth: .infinity).padding(14)
                                    .background(Color.purple).clipShape(RoundedRectangle(cornerRadius: 13))
                                    .foregroundStyle(.white)
                                }
                                .disabled(isBusy || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            VStack(alignment: .leading, spacing: 9) {
                                Link(destination: URL(string: "https://github.com/signup")!) {
                                    Label("إنشاء حساب GitHub جديد", systemImage: "person.badge.plus")
                                }
                                Link(destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!) {
                                    Label("إنشاء رمز وصول للتطبيق", systemImage: "key.fill")
                                }
                                Text("الصلاحيات المطلوبة عند إنشاء الرمز: Contents (Read and write)، Actions (Read and write)، وMetadata (Read-only). لا ترسل الرمز لأي شخص.")
                                    .font(.caption).foregroundStyle(.white.opacity(0.58))
                            }
                            .tint(.purple)
                        }

                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(status.hasPrefix("تعذر") ? .red : .white.opacity(0.72))
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("الحساب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("إغلاق") { dismiss() }.foregroundStyle(.white)
                }
            }
            .task { loadConnectionState() }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
    }

    private func loadConnectionState() {
        guard GitHubTokenStore.read() != nil else { return }
        isConnected = true
        accountName = "تم حفظ الرمز، اضغط ربط الحساب مجدداً للتحقق"
        status = "يوجد رمز محفوظ في Keychain على هذا الجهاز."
    }

    private func connect() {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }
        isBusy = true
        status = "جاري التحقق من الرمز عبر GitHub..."
        Task {
            defer { isBusy = false }
            do {
                var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
                request.httpMethod = "GET"
                request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                request.setValue("PS4TOOLS-MOBILE", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw GitHubAccountError.invalidToken
                }
                let payload = try JSONDecoder().decode(GitHubUser.self, from: data)
                try GitHubTokenStore.save(cleanToken)
                accountName = payload.login
                isConnected = true
                token = ""
                status = "تم التحقق من الحساب وحفظ الرمز بأمان في Keychain."
            } catch {
                status = "تعذر ربط الحساب: \(error.localizedDescription)"
            }
        }
    }

    private func disconnect() {
        GitHubTokenStore.delete()
        isConnected = false
        accountName = ""
        status = "تم حذف رمز GitHub المحفوظ من هذا الجهاز."
    }
}

private struct GitHubUser: Decodable {
    let login: String
}

private enum GitHubAccountError: LocalizedError {
    case invalidToken
    var errorDescription: String? {
        "الرمز غير صالح أو لا يملك صلاحية قراءة الحساب."
    }
}

private enum GitHubTokenStore {
    private static let service = "com.tmoath07.ps4toolsmobile.github"
    private static let account = "personal-access-token"

    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GitHubAccountError.invalidToken
        }
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct ModGuideView: View {
    @Environment(\.dismiss) private var dismiss
    private let sections: [(String, String, String)] = [
        ("1. استيراد المود", "اضغط ملف ZIP / RAR أو مجلد من تطبيق «الملفات». اختر العنصر وانتظر رسالة نجاح الاستيراد.", "doc.badge.arrow.up"),
        ("2. تجهيز الملفات", "استخدم زر فك الملفات لإنشاء نسخة عمل مستقلة. الملف الأصلي يبقى محفوظاً ولا يتم تعديله.", "shippingbox"),
        ("3. أسماء DLC", "اكتب اسم الحزمة بحروف إنجليزية وأرقام وشرطة سفلية فقط، ثم أنشئ ملف dlclist.xml.", "list.bullet.rectangle"),
        ("4. حساب GitHub", "اربط حسابك من أيقونة الحساب. لا تكتب كلمة مرور GitHub؛ استخدم رمز وصول شخصي واحفظه داخل Keychain.", "person.crop.circle"),
        ("5. التحويل الفعلي", "تحويل أصول PC إلى PS4 يحتاج أدوات التحويل السحابية في GitHub Actions. تجهيز ZIP أو إنشاء XML وحده لا يعني أن المود تحول إلى PS4.", "gearshape.2")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.035, green: 0.025, blue: 0.065).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("شرح PS4TOOLS MOBILE")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("دليل سريع لاستخدام التطبيق ومعرفة حدود كل خطوة.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                        ForEach(sections, id: \.0) { title, detail, symbol in
                            VStack(alignment: .leading, spacing: 8) {
                                Label(title, systemImage: symbol)
                                    .font(.headline).foregroundStyle(.purple)
                                Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.76))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(15)
                            .background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("الشرح")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("إغلاق") { dismiss() }.foregroundStyle(.white)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
    }
}
