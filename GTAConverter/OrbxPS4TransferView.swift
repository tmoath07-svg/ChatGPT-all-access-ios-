import SwiftUI

struct OrbxPS4TransferView: View {
    let packageURL: URL?
    let initialPackNames: [String]

    @AppStorage("inrpf_ps4_host") private var host = ""
    @AppStorage("inrpf_ps4_port") private var port = "2121"
    @AppStorage("inrpf_ps4_username") private var username = "anonymous"
    @State private var availablePackages: [URL] = []
    @State private var selectedPackagePath = ""
    @State private var packNames: [String] = []
    @State private var password = ""
    @State private var isBusy = false
    @State private var status = "أدخل عنوان PS4 بعد تفعيل FTP في GoldHEN. سيتم رفع مجلدات DLC ودمج dlclist.xml."
    @State private var isError = false
    @State private var uploadedFiles = 0

    private let remoteRoot = "/data/orbx/gta/rpf"
    private var purple: Color { Color(red: 0.70, green: 0.42, blue: 0.88) }
    private var selectedPackageURL: URL? { availablePackages.first { $0.path == selectedPackagePath } }

    init(packageURL: URL? = nil, packNames: [String] = []) {
        self.packageURL = packageURL
        self.initialPackNames = packNames
        _selectedPackagePath = State(initialValue: packageURL?.path ?? "")
        _packNames = State(initialValue: packNames)
    }

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("إرسال حزمة Orbx إلى PS4", systemImage: "gamecontroller.fill")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("يرفع ملفات الحزم إلى dlc_addon، ثم يدمج أسماءها داخل dlclist.xml الموجود على الجهاز بدلاً من استبدال محتواه.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(17).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 9) {
                        Label("حزمة المود الجاهزة", systemImage: "shippingbox.fill")
                            .font(.subheadline.bold()).foregroundStyle(purple)
                        if availablePackages.isEmpty {
                            Text("ما فيه حزمة Orbx جاهزة. جهّز الحزمة أولاً من شاشة حزم PS4.")
                                .font(.caption).foregroundStyle(.orange)
                        } else {
                            Picker("اختر الحزمة", selection: $selectedPackagePath) {
                                ForEach(availablePackages, id: \.path) { item in
                                    Text(item.lastPathComponent).tag(item.path)
                                }
                            }
                            .pickerStyle(.menu).tint(.white)
                            .onChange(of: selectedPackagePath) { _, _ in loadSelectedPackageNames() }
                            Text("عدد الحزم داخلها: \(packNames.count)")
                                .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(14).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 15))

                    VStack(spacing: 11) {
                        field("IP جهاز PS4", text: $host, placeholder: "مثال: 192.168.1.50")
                            .keyboardType(.numbersAndPunctuation)
                        field("المنفذ", text: $port, placeholder: "2121")
                            .keyboardType(.numberPad)
                        field("اسم المستخدم", text: $username, placeholder: "anonymous")
                        VStack(alignment: .leading, spacing: 5) {
                            Text("كلمة المرور").font(.caption).foregroundStyle(.white.opacity(0.6))
                            SecureField("كلمة المرور", text: $password)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(12).background(.black.opacity(0.22))
                                .clipShape(RoundedRectangle(cornerRadius: 11)).foregroundStyle(.white)
                        }
                    }
                    .padding(15).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 7) {
                        Label("المسار المستهدف", systemImage: "folder.fill")
                            .font(.subheadline.bold()).foregroundStyle(purple)
                        Text(remoteRoot + "/dlc_addon/")
                            .font(.caption.monospaced()).foregroundStyle(.white).textSelection(.enabled)
                        Text("ملف القائمة: " + remoteRoot + "/dlclist.xml")
                            .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7)).textSelection(.enabled)
                        Text("الحزم: " + packNames.joined(separator: "، "))
                            .font(.caption).foregroundStyle(.white.opacity(0.62))
                    }
                    .padding(14).background(.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button(action: sendPackage) {
                        HStack(spacing: 9) {
                            if isBusy { ProgressView().tint(.white) }
                            Label(isBusy ? "جاري الإرسال..." : "إرسال المود إلى السوني", systemImage: "arrow.up.to.line")
                                .font(.headline.bold())
                        }
                        .frame(maxWidth: .infinity).padding(16)
                        .background(purple).clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || packNames.isEmpty || selectedPackageURL == nil)

                    Text("الملفات المرفوعة: \(uploadedFiles)")
                        .font(.caption.bold()).foregroundStyle(purple)
                    Text(status)
                        .font(.caption).foregroundStyle(isError ? .red : .white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13).background(.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("تنبيه: الإرسال لا يحوّل RPF من صيغة PC إلى PS4. استخدمه فقط بعد تجهيز ملفات متوافقة فعلياً، وتأكد أن مسار Orbx على جهازك هو المسار الموضح.")
                        .font(.caption2).foregroundStyle(.orange.opacity(0.9))
                        .padding(12).background(.orange.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding(16)
            }
        }
        .navigationTitle("إرسال إلى PS4")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear(perform: discoverPackages)
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.6))
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(.black.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 11)).foregroundStyle(.white)
        }
    }

    private func sendPackage() {
        guard let portNumber = UInt16(port), portNumber > 0 else {
            status = "المنفذ غير صالح."
            isError = true
            return
        }
        let base = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username
        let pass = password
        guard let package = selectedPackageURL else {
            status = "اختر حزمة Orbx جاهزة أولاً."
            isError = true
            return
        }
        let names = packNames
        let portValue = portNumber
        isBusy = true
        isError = false
        uploadedFiles = 0
        status = "جارٍ الاتصال بجهاز PS4..."
        Task.detached(priority: .userInitiated) {
            do {
                _ = try LocalEngineBridge.ftpConnect(host: base, port: portValue, username: user, password: pass)
                let fm = FileManager.default
                let addon = package.appendingPathComponent("data/orbx/gta/rpf/dlc_addon", isDirectory: true)
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: addon.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw NSError(domain: "INRPF.Transfer", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "مجلد dlc_addon غير موجود داخل الحزمة."])
                }

                try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: "/data")
                try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: "/data/orbx")
                try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: "/data/orbx/gta")
                try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: "/data/orbx/gta/rpf")
                try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: "/data/orbx/gta/rpf/dlc_addon")

                var count = 0
                for name in names {
                    let localPack = addon.appendingPathComponent(name, isDirectory: true)
                    guard fm.fileExists(atPath: localPack.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                        throw NSError(domain: "INRPF.Transfer", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "مجلد الحزمة غير موجود: \(name)"])
                    }
                    let remotePack = "/data/orbx/gta/rpf/dlc_addon/\(name)"
                    try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: remotePack)
                    guard let enumerator = fm.enumerator(at: localPack, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                        throw NSError(domain: "INRPF.Transfer", code: 3,
                                      userInfo: [NSLocalizedDescriptionKey: "تعذر قراءة مجلد \(name)"])
                    }
                    for case let file as URL in enumerator {
                        let values = try file.resourceValues(forKeys: [.isDirectoryKey])
                        let relative = String(file.path.dropFirst(localPack.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let components = relative.split(separator: "/").map(String.init)
                        if values.isDirectory == true {
                            let remote = components.reduce(remotePack) { $0 + "/" + $1 }
                            try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: remote)
                        } else {
                            let remoteParent = components.dropLast().reduce(remotePack) { $0 + "/" + $1 }
                            if remoteParent != remotePack {
                                try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: remoteParent)
                            }
                            _ = try LocalEngineBridge.ftpUpload(host: base, port: portValue, username: user,
                                password: pass, path: remoteParent, name: file.lastPathComponent, localFile: file)
                            count += 1
                        }
                    }
                }

                let temp = fm.temporaryDirectory.appendingPathComponent("inrpf-dlclist-\(UUID().uuidString).xml")
                let remoteRPF = "/data/orbx/gta/rpf"
                let remoteEntries = try LocalEngineBridge.ftpList(host: base, port: portValue,
                    username: user, password: pass, path: remoteRPF)["entries"] as? [[String: Any]] ?? []
                let hasExistingList = remoteEntries.contains {
                    ($0["name"] as? String)?.caseInsensitiveCompare("dlclist.xml") == .orderedSame
                }
                var merged: String
                if hasExistingList {
                    _ = try LocalEngineBridge.ftpDownload(host: base, port: portValue, username: user,
                        password: pass, path: remoteRPF, name: "dlclist.xml", destination: temp)
                    merged = try String(contentsOf: temp, encoding: .utf8)
                    guard merged.range(of: "</Paths>", options: .caseInsensitive) != nil else {
                        throw NSError(domain: "INRPF.Transfer", code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "تعذر قراءة dlclist.xml الموجود أو لا يحتوي على </Paths>. لم نستبدله حفاظاً على قائمتك."])
                    }
                } else {
                    merged = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<SMandatoryPacksData>\n  <Paths>\n  </Paths>\n</SMandatoryPacksData>"
                }
                try? fm.removeItem(at: temp)
                for name in names {
                    let entry = "<Item>/data/orbx/gta/rpf/dlc_addon/\(name)/</Item>"
                    if !merged.localizedCaseInsensitiveContains(entry) {
                        guard let close = merged.range(of: "</Paths>", options: .caseInsensitive) else {
                            throw NSError(domain: "INRPF.Transfer", code: 4,
                                userInfo: [NSLocalizedDescriptionKey: "ملف dlclist.xml الموجود لا يحتوي على عنصر </Paths>، أوقفنا الرفع حتى لا نتلفه."])
                        }
                        merged.insert(contentsOf: "    \(entry)\n  ", at: close.lowerBound)
                    }
                }
                let outputXML = fm.temporaryDirectory.appendingPathComponent("dlclist-\(UUID().uuidString).xml")
                try merged.write(to: outputXML, atomically: true, encoding: .utf8)
                _ = try LocalEngineBridge.ftpUpload(host: base, port: portValue, username: user,
                    password: pass, path: remoteRPF, name: "dlclist.xml", localFile: outputXML)
                try? fm.removeItem(at: outputXML)

                let completedFileCount = count
                await MainActor.run {
                    uploadedFiles = completedFileCount
                    status = "اكتمل رفع \(names.count) حزمة و\(completedFileCount) ملف، وتم دمج dlclist.xml دون حذف المسارات السابقة."
                    isBusy = false
                    isError = false
                }
            } catch {
                await MainActor.run {
                    status = "توقف الإرسال: \(error.localizedDescription)"
                    isBusy = false
                    isError = true
                }
            }
        }
    }

    nonisolated private static func ensureRemoteDirectory(host: String, port: UInt16, username: String, password: String, fullPath: String) throws {
        let parts = fullPath.split(separator: "/").map(String.init)
        var parent = "/"
        for part in parts {
            let current = parent == "/" ? "/" + part : parent + "/" + part
            do {
                _ = try LocalEngineBridge.ftpList(host: host, port: port, username: username,
                                                   password: password, path: current)
            } catch {
                _ = try LocalEngineBridge.ftpMakeDirectory(host: host, port: port, username: username,
                                                             password: password, path: parent, name: part)
                _ = try LocalEngineBridge.ftpList(host: host, port: port, username: username,
                                                   password: password, path: current)
            }
            parent = current
        }
    }

    private func discoverPackages() {
        let ready = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTA Converter/Ready", isDirectory: true)
        let found = (try? FileManager.default.contentsOfDirectory(at: ready,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        availablePackages = found.filter {
            $0.lastPathComponent.hasPrefix("PS4-Orbx-") &&
            ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }

        if let packageURL, !availablePackages.contains(where: { $0.path == packageURL.path }) {
            availablePackages.insert(packageURL, at: 0)
        }
        if selectedPackagePath.isEmpty, let first = availablePackages.first {
            selectedPackagePath = first.path
        }
        loadSelectedPackageNames()
    }

    private func loadSelectedPackageNames() {
        guard let selectedPackageURL else { packNames = []; return }
        if !initialPackNames.isEmpty, packageURL?.path == selectedPackageURL.path {
            packNames = initialPackNames
            return
        }
        let addon = selectedPackageURL.appendingPathComponent("data/orbx/gta/rpf/dlc_addon", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: addon,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        packNames = folders.filter {
            ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) &&
            $0.lastPathComponent.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil
        }.map(\.lastPathComponent).sorted()
    }
}
