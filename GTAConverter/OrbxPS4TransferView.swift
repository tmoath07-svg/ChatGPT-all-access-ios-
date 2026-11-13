import SwiftUI

struct OrbxPS4TransferView: View {
    let packageURL: URL?
    let initialPackNames: [String]
    let autoStart: Bool

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
    @State private var didAutoStart = false

    private let remoteRoot = "/Data/orbx/gta/rpf"
    private let remoteDLClistDirectory = "/Data/orbx/gta"
    private var purple: Color { Color(red: 0.70, green: 0.42, blue: 0.88) }
    private var selectedPackageURL: URL? { availablePackages.first { $0.path == selectedPackagePath } }

    init(packageURL: URL? = nil, packNames: [String] = [], autoStart: Bool = false) {
        self.packageURL = packageURL
        self.initialPackNames = packNames
        self.autoStart = autoStart
        _selectedPackagePath = State(initialValue: packageURL?.path ?? "")
        _packNames = State(initialValue: packNames)
    }

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("تركيب Auto لحزم Orbx على PS4", systemImage: "gamecontroller.fill")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("زر واحد يفحص الحزم، يرفعها إلى dlc_addon، يدمج مساراتها في dlclist.xml ويحفظ نسخة احتياطية من القائمة القديمة قبل تحديثها.")
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
                            .onChange(of: selectedPackagePath) { _ in loadSelectedPackageNames() }
                            Text("عدد الحزم داخلها: \(packNames.count)")
                                .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .padding(14).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 15))

                    VStack(spacing: 11) {
                        field("عنوان جهاز PS4 (IP)", text: $host, placeholder: "192.168.1.50")
                            .keyboardType(.numbersAndPunctuation)
                        field("المنفذ", text: $port, placeholder: "2121")
                            .keyboardType(.numberPad)
                        field("اسم المستخدم", text: $username, placeholder: "anonymous")
                        VStack(alignment: .leading, spacing: 5) {
                            Text("كلمة المرور").font(.caption).foregroundStyle(.white.opacity(0.6))
                            SecureField("كلمة المرور", text: $password)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .environment(\.layoutDirection, .leftToRight)
                                .multilineTextAlignment(.leading)
                                .padding(12).background(.black.opacity(0.22))
                                .clipShape(RoundedRectangle(cornerRadius: 11)).foregroundStyle(.white)
                        }
                    }
                    .padding(15).background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 7) {
                        Label("المسار المستهدف", systemImage: "folder.fill")
                            .font(.subheadline.bold()).foregroundStyle(purple)
                        Text("مجلد الحزم على PS4")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                        Text(remoteRoot + "/dlc_addon/")
                            .font(.caption.monospaced()).foregroundStyle(.white)
                            .environment(\.layoutDirection, .leftToRight)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        Text("ملف القائمة على PS4")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                        Text(remoteDLClistDirectory + "/dlclist.xml")
                            .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.85))
                            .environment(\.layoutDirection, .leftToRight)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        Text("الحزم: " + packNames.joined(separator: "، "))
                            .font(.caption).foregroundStyle(.white.opacity(0.62))
                    }
                    .padding(14).background(.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Button(action: sendPackage) {
                        HStack(spacing: 9) {
                            if isBusy { ProgressView().tint(.white) }
                            Label(isBusy ? "جاري تركيب Auto..." : "تركيب Auto بنقرة واحدة", systemImage: "bolt.fill")
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
        .onAppear {
            discoverPackages()
            guard autoStart, !didAutoStart else { return }
            didAutoStart = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sendPackage() }
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.6))
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
                .multilineTextAlignment(.leading)
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
        guard !base.isEmpty else {
            status = "أدخل IP جهاز PS4 أولاً. لم يبدأ النقل."
            isError = true
            return
        }
        guard let package = selectedPackageURL else {
            status = "اختر حزمة Orbx جاهزة أولاً."
            isError = true
            return
        }
        let addon = package.appendingPathComponent("Data/orbx/gta/rpf/dlc_addon", isDirectory: true)
        let names: [String]
        do {
            names = try INRPFOrbxAutoInstallPlanner.discoverPackageNames(in: addon)
        } catch {
            status = error.localizedDescription
            isError = true
            return
        }

        let portValue = portNumber
        isBusy = true
        isError = false
        uploadedFiles = 0
        status = "فحص الحزم وملف dlclist.xml قبل الرفع..."
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let remoteRPF = INRPFOrbxAutoInstallPlanner.remoteRoot
            let remoteAddon = INRPFOrbxAutoInstallPlanner.remoteAddon
            let remoteListDirectory = INRPFOrbxAutoInstallPlanner.remoteDLClistDirectory
            let listTemp = fm.temporaryDirectory.appendingPathComponent("inrpf-dlclist-original-\(UUID().uuidString).xml")
            let outputXML = fm.temporaryDirectory.appendingPathComponent("inrpf-dlclist-merged-\(UUID().uuidString).xml")
            let verifyXML = fm.temporaryDirectory.appendingPathComponent("inrpf-dlclist-verify-\(UUID().uuidString).xml")

            do {
                _ = try LocalEngineBridge.ftpConnect(host: base, port: portValue, username: user, password: pass)
                try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: remoteRPF)
                try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: remoteAddon)

                let remoteEntries = try LocalEngineBridge.ftpList(host: base, port: portValue,
                    username: user, password: pass, path: remoteListDirectory)["entries"] as? [[String: Any]] ?? []
                let hasExistingList = remoteEntries.contains {
                    ($0["name"] as? String)?.caseInsensitiveCompare("dlclist.xml") == .orderedSame
                }

                guard hasExistingList else {
                    throw NSError(domain: "INRPF.Transfer", code: 7,
                        userInfo: [NSLocalizedDescriptionKey: "ما لقيت dlclist.xml داخل ORBX/GTA. أوقفت التركيب حتى ما أنشئ قائمة جديدة وأمسح قائمتك بالغلط."])
                }
                _ = try LocalEngineBridge.ftpDownload(host: base, port: portValue, username: user,
                    password: pass, path: remoteListDirectory, name: "dlclist.xml", destination: listTemp)
                let originalXML = try String(contentsOf: listTemp, encoding: .utf8)

                // Validate all local DLC archives as vehicle packages before any FTP upload.
                for name in names {
                    let packageFolder = addon.appendingPathComponent(name, isDirectory: true)
                    let localPack = try INRPFOrbxAutoInstallPlanner.packageContentRoot(for: packageFolder)
                    let localDLC = localPack.appendingPathComponent("dlc.rpf")
                    guard fm.fileExists(atPath: localDLC.path) else {
                        throw NSError(domain: "INRPF.Transfer", code: 8,
                            userInfo: [NSLocalizedDescriptionKey: "حزمة المركبة لا تحتوي dlc.rpf في المسار المتوقع: \(name)"])
                    }
                    // Inspect the archive structurally. RPF inspection is format validation,
                    // not a vehicle-only filter; DLC package validation remains separate.
                    _ = try LocalEngineBridge.inspectRPF(at: localDLC)
                    _ = try LocalEngineBridge.listRPF(at: localDLC)
                }

                // Validate and merge before uploading any DLC files.
                let merged = try INRPFOrbxAutoInstallPlanner.mergedDLClist(existing: originalXML, packageNames: names)
                if hasExistingList {
                    let backupName = "dlclist.xml.inrpf-backup-\(Int(Date().timeIntervalSince1970))"
                    _ = try LocalEngineBridge.ftpUpload(host: base, port: portValue, username: user,
                        password: pass, path: remoteListDirectory, name: backupName, localFile: listTemp)
                }

                var count = 0
                for name in names {
                    let packageFolder = addon.appendingPathComponent(name, isDirectory: true)
                    var isDirectory: ObjCBool = false
                    guard fm.fileExists(atPath: packageFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                        throw NSError(domain: "INRPF.Transfer", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "مجلد الحزمة غير موجود: \(name)"])
                    }
                    let localPack = try INRPFOrbxAutoInstallPlanner.packageContentRoot(for: packageFolder)
                    let remotePack = remoteAddon + "/" + name
                    try Self.ensureRemoteDirectory(host: base, port: portValue, username: user, password: pass, fullPath: remotePack)
                    guard let enumerator = fm.enumerator(at: localPack,
                        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                        options: [.skipsHiddenFiles]) else {
                        throw NSError(domain: "INRPF.Transfer", code: 3,
                                      userInfo: [NSLocalizedDescriptionKey: "تعذر قراءة مجلد \(name)"])
                    }

                    for case let file as URL in enumerator {
                        let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        if values.isSymbolicLink == true { continue }
                        let relative = String(file.path.dropFirst(localPack.path.count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let components = relative.split(separator: "/").map(String.init)
                        guard !components.contains(".."), !components.contains(".") else {
                            throw NSError(domain: "INRPF.Transfer", code: 5,
                                userInfo: [NSLocalizedDescriptionKey: "مسار داخلي غير صالح داخل الحزمة: \(relative)"])
                        }
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

                try merged.write(to: outputXML, atomically: true, encoding: .utf8)
                _ = try LocalEngineBridge.ftpUpload(host: base, port: portValue, username: user,
                    password: pass, path: remoteListDirectory, name: "dlclist.xml", localFile: outputXML)

                // Verify the deployed list by downloading it again.
                _ = try LocalEngineBridge.ftpDownload(host: base, port: portValue, username: user,
                    password: pass, path: remoteListDirectory, name: "dlclist.xml", destination: verifyXML)
                let deployed = try String(contentsOf: verifyXML, encoding: .utf8)
                let verified = try INRPFOrbxAutoInstallPlanner.mergedDLClist(existing: deployed, packageNames: names)
                guard verified == deployed else {
                    throw NSError(domain: "INRPF.Transfer", code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "فشل التحقق من وجود جميع مسارات DLC داخل dlclist.xml بعد الرفع."])
                }

                let completedFileCount = count
                await MainActor.run {
                    uploadedFiles = completedFileCount
                    status = "اكتمل تركيب Auto: \(names.count) حزمة و\(completedFileCount) ملف. تم التحقق من dlclist.xml."
                    isBusy = false
                    isError = false
                }
            } catch {
                await MainActor.run {
                    status = "توقف تركيب Auto: \(error.localizedDescription)"
                    isBusy = false
                    isError = true
                }
            }
            try? fm.removeItem(at: listTemp)
            try? fm.removeItem(at: outputXML)
            try? fm.removeItem(at: verifyXML)
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
        let addon = selectedPackageURL.appendingPathComponent("Data/orbx/gta/rpf/dlc_addon", isDirectory: true)
        packNames = (try? INRPFOrbxAutoInstallPlanner.discoverPackageNames(in: addon)) ?? []
    }
}
