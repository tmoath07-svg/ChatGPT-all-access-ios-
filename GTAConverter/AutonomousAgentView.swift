import SwiftUI

struct AutonomousAgentView: View {
    @StateObject private var providers = AIProviderStore()
    @State private var providerName = ""
    @State private var baseURL = "https://freemodel.in/v1"
    @State private var apiKey = ""
    @State private var modelID = ""
    @State private var discoveredModels: [String] = []
    @State private var isLoadingModels = false
    @State private var showingProviderEditor = false
    @State private var errorText = ""
    @State private var statusText = ""

    @AppStorage("inrpf.agent.ps4.host") private var ps4Host = ""
    @AppStorage("inrpf.agent.ps4.port") private var ps4Port = "2121"
    @AppStorage("inrpf.agent.ps4.username") private var ps4Username = "anonymous"
    @State private var ps4Password = ""

    @State private var input = ""
    @State private var messages: [AgentChatMessage] = []
    @State private var isSending = false
    @State private var connectionEnabled = false

    private var agent: AutonomousAgentService { AutonomousAgentService(providerStore: providers) }

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        providerPanel
                        ftpPanel
                        chatPanel(proxy: proxy)
                    }
                    .padding(16)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationTitle("INRPF AI Agent")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingProviderEditor) { providerEditor }
        .onAppear {
            if let selected = providers.selectedProvider {
                providerName = selected.name
                baseURL = selected.baseURL
                modelID = selected.modelID
            }
            ps4Password = (try? AgentConnectionStore.loadPassword()) ?? ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AUTONOMOUS AI AGENT", systemImage: "brain.head.profile")
                .font(.headline).foregroundStyle(.white)
            Text("مساعد ينفّذ المهام باستخدام أدوات INRPF الفعلية، ويشخّص مشاكل التطبيق ويقرأ ملفات PS4 عبر FTP.")
                .font(.caption).foregroundStyle(.white.opacity(0.68))
            HStack(spacing: 7) {
                Label("AI Providers", systemImage: "point.3.connected.trianglepath.dotted")
                Label("PS4 FTP", systemImage: "network")
                Label("Self Diagnostics", systemImage: "stethoscope")
            }
            .font(.caption2.bold()).foregroundStyle(.purple)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var providerPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("مزودات الذكاء الاصطناعي", systemImage: "cpu")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                Button { showingProviderEditor = true } label: {
                    Label("إضافة", systemImage: "plus").font(.caption.bold())
                }
            }
            if providers.providers.isEmpty {
                Text("أضف مزود API لتشغيل الوكيل. مفاتيح API تحفظ في Keychain.")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            } else {
                Picker("المزود", selection: Binding(
                    get: { providers.selectedProviderID ?? providers.providers.first?.id ?? "" },
                    set: { providers.select($0) }
                )) {
                    ForEach(providers.providers) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                .tint(.white)
                if let selected = providers.selectedProvider {
                    Text("Base URL: \(selected.baseURL)")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))
                    TextField("Model ID", text: $modelID)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(11).background(.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 10))
                    HStack {
                        Button("حفظ النموذج") { providers.selectModel(modelID, for: selected.id) }
                        Button("حذف المزود", role: .destructive) { providers.remove(selected) }
                    }.font(.caption.bold())
                }
            }
            if !statusText.isEmpty { Text(statusText).font(.caption).foregroundStyle(.green) }
            if !errorText.isEmpty { Text(errorText).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(15).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var providerEditor: some View {
        NavigationStack {
            Form {
                Section("إعدادات المزود") {
                    TextField("Provider Name", text: $providerName)
                    TextField("Base URL", text: $baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API Key", text: $apiKey)
                    TextField("Model ID (اختياري)", text: $modelID).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section {
                    Button {
                        Task { await discoverModels() }
                    } label: {
                        HStack {
                            if isLoadingModels { ProgressView() }
                            Text("جلب النماذج")
                        }
                    }.disabled(isLoadingModels)
                    ForEach(discoveredModels, id: \.self) { model in
                        Button {
                            modelID = model
                        } label: {
                            HStack {
                                Text(model)
                                Spacer()
                                if modelID == model { Image(systemName: "checkmark").foregroundStyle(.green) }
                            }
                        }
                    }
                }
                Section {
                    Button("حفظ المزود") { saveProvider() }
                        .disabled(providerName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  baseURL.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("إضافة مزود")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("إغلاق") { showingProviderEditor = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var ftpPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("اتصال PS4 عبر FTP", systemImage: "network")
                .font(.headline).foregroundStyle(.white)
            TextField("IP Address", text: $ps4Host)
                .keyboardType(.decimalPad).textInputAutocapitalization(.never)
                .padding(10).background(.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack {
                TextField("Port", text: $ps4Port).keyboardType(.numberPad)
                TextField("Username", text: $ps4Username).textInputAutocapitalization(.never)
            }
            .padding(10).background(.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 10))
            SecureField("FTP Password (إن وجد)", text: $ps4Password)
                .padding(10).background(.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 10))
            Toggle("إتاحة أدوات القراءة للوكيل", isOn: $connectionEnabled).tint(.purple)
            Button("حفظ إعدادات FTP") {
                do {
                    try AgentConnectionStore.savePassword(ps4Password)
                    statusText = "تم حفظ كلمة مرور FTP في Keychain."
                    errorText = ""
                } catch { errorText = error.localizedDescription }
            }
            .font(.caption.bold())
            Text("أدوات FTP المتاحة حالياً للوكيل للقراءة فقط: استعراض المجلدات والبحث عن الملفات. لا يوجد حذف تلقائي.")
                .font(.caption2).foregroundStyle(.orange)
        }
        .padding(15).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func chatPanel(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("محادثة الوكيل", systemImage: "sparkles")
                .font(.headline).foregroundStyle(.white)
            if messages.isEmpty {
                Text("مثال: افحص اتصال PS4 وابحث عن ملفات GTA IV داخل /data.")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            ForEach(messages) { message in
                VStack(alignment: .leading, spacing: 5) {
                    Text(message.role == "user" ? "أنت" : "INRPF AI")
                        .font(.caption2.bold()).foregroundStyle(message.role == "user" ? .purple : .green)
                    Text(message.text).font(.subheadline).foregroundStyle(.white)
                        .textSelection(.enabled)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(message.role == "user" ? 0.10 : 0.055))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .id(message.id)
            }
            TextField("اكتب أمرك...", text: $input, axis: .vertical)
                .lineLimit(2...5).padding(12)
                .background(.black.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 12))
            Button {
                Task { await sendMessage(proxy: proxy) }
            } label: {
                HStack {
                    if isSending { ProgressView().tint(.white) }
                    Label("إرسال إلى الوكيل", systemImage: "paperplane.fill")
                }
                .font(.headline).frame(maxWidth: .infinity).padding(13)
                .background(.purple).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(15).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func saveProvider() {
        do {
            try providers.save(name: providerName, baseURL: baseURL, apiKey: apiKey, modelID: modelID)
            statusText = "تم حفظ المزود ومفتاحه بأمان."
            errorText = ""
            apiKey = ""
            showingProviderEditor = false
        } catch { errorText = error.localizedDescription }
    }

    private func discoverModels() async {
        isLoadingModels = true
        errorText = ""
        defer { isLoadingModels = false }
        do {
            discoveredModels = try await AIProviderAPI.fetchModels(baseURL: baseURL, apiKey: apiKey)
            statusText = "تم اكتشاف \(discoveredModels.count) نموذجاً."
        } catch { errorText = error.localizedDescription }
    }

    private func sendMessage(proxy: ScrollViewProxy) async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        messages.append(AgentChatMessage(role: "user", text: text))
        isSending = true
        errorText = ""
        defer { isSending = false }
        let connection: PS4AgentConnection?
        if connectionEnabled, let port = UInt16(ps4Port), !ps4Host.isEmpty {
            connection = try? PS4AgentConnection(host: ps4Host, port: port,
                                                  username: ps4Username,
                                                  password: AgentConnectionStore.loadPassword())
        } else {
            connection = nil
        }
        do {
            let answer = try await agent.send(userText: text, history: Array(messages.dropLast()), connection: connection)
            messages.append(AgentChatMessage(role: "assistant", text: answer))
        } catch {
            messages.append(AgentChatMessage(role: "assistant", text: "تعذر تنفيذ الطلب: \(error.localizedDescription)"))
        }
        if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
    }
}
