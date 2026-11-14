import SwiftUI
import UniformTypeIdentifiers
import SwiftArchive

struct ContentView: View {
    @State private var showingImporter = false
    @State private var showingAccount = false
    @State private var showingGuide = false
    @State private var sourceURL: URL?
    @State private var selectedFileName = "ما تم اختيار ملف"
    @State private var directURL = ""
    @State private var packNames = ""
    @State private var generatedURL: URL?
    @State private var outputFolder: URL?
    @State private var status = "اختر ZIP أو RAR أو مجلداً، أو الصق رابط تحميل مباشر."
    @State private var isError = false
    @State private var isBusy = false
    @State private var progressText = ""
    @State private var importKind = ImportKind.archive

    private let purple = Color(red: 0.57, green: 0.30, blue: 0.98)
    private let background = Color(red: 0.035, green: 0.025, blue: 0.065)

    private enum ImportKind: String, CaseIterable, Identifiable {
        case archive = "ZIP / RAR"
        case folder = "مجلد"
        var id: String { rawValue }
    }

    private var names: [String] {
        packNames.split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        importCard
                        directLinkCard
                        packCard
                        actionButtons
                        if let outputFolder { outputCard(outputFolder) }
                        if let generatedURL { xmlShareCard(generatedURL) }
                        statusCard
                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("PS4TOOLS MOBILE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingAccount = true } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("تسجيل الدخول")
                    Button { showingGuide = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("شرح التطبيق")
                }
            }
            .sheet(isPresented: $showingImporter) {
                ModDocumentPicker(
                    allowedContentTypes: importKind == .folder ? [.folder] : [.zip, .rar, .item],
                    onPick: { pickedURL in handleImport(.success([pickedURL])) },
                    onCancel: {}
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingAccount) { GitHubAccountView() }
            .sheet(isPresented: $showingGuide) { ModGuideView() }
            .disabled(isBusy)
            .overlay {
                if isBusy {
                    ZStack {
                        Color.black.opacity(0.58).ignoresSafeArea()
                        VStack(spacing: 14) {
                            ProgressView().tint(.white).scaleEffect(1.25)
                            Text(progressText.isEmpty ? "جاري تجهيز الملفات..." : progressText)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(26)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(purple)
                Spacer()
                Text("iOS / iPadOS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.2)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(purple.opacity(0.22))
                    .clipShape(Capsule())
            }
            Text("PS4TOOLS MOBILE")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text("جهّز ملفات مودات قراند للـ PS4")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 7) {
                featureTag("ZIP")
                featureTag("RAR")
                featureTag("رابط مباشر")
                featureTag("مجلدات")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(19)
        .background(LinearGradient(colors: [purple.opacity(0.34), Color.white.opacity(0.035)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.07)))
    }

    private func featureTag(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.white.opacity(0.09)).clipShape(Capsule())
            .foregroundStyle(.white.opacity(0.8))
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("استيراد المود", icon: "tray.and.arrow.down.fill")
            HStack(spacing: 8) {
                importButton("ملف ZIP / RAR", icon: "doc.zipper", kind: .archive)
                importButton("مجلد من الملفات", icon: "folder", kind: .folder)
            }
            HStack(spacing: 11) {
                Image(systemName: sourceURL == nil ? "doc" : "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(sourceURL == nil ? .white.opacity(0.35) : .green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedFileName).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                    Text(sourceURL == nil ? "لم يتم اختيار مصدر بعد" : "جاهز للمعالجة")
                        .font(.caption).foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 0)
                if sourceURL != nil {
                    Button { sourceURL = nil; selectedFileName = "ما تم اختيار ملف" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12).background(.black.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 13))
            Text("تقدر تختار الملف من تطبيق «الملفات» في الآيفون.")
                .font(.caption).foregroundStyle(.white.opacity(0.48))
        }
        .padding(16).panel()
    }

    private func importButton(_ title: String, icon: String, kind: ImportKind) -> some View {
        Button {
            importKind = kind
            showingImporter = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Text(title).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 76)
            .background(purple.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(purple.opacity(0.32)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var directLinkCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("تحميل من رابط مباشر", icon: "link")
            TextField("https://example.com/mod.zip أو .rar", text: $directURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
                .padding(14)
                .background(.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            Button(action: downloadFromLink) {
                Label("تحميل الرابط واستيراده", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity).padding(14)
                    .background(.white.opacity(0.09)).clipShape(RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16).panel()
    }

    private var packCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("أسماء مجلدات DLC", icon: "list.bullet.rectangle")
            Text("اسم واحد في كل سطر، بدون مسافات أو رموز غريبة.")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
            TextEditor(text: $packNames)
                .frame(minHeight: 112, maxHeight: 155)
                .scrollContentBackground(.hidden)
                .padding(9)
                .background(.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text("\(names.count) اسم صالح")
                .font(.caption2).foregroundStyle(purple)
        }
        .padding(16).panel()
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button(action: processSource) {
                Label("فك الملفات وتجهيز نسخة احتياطية", systemImage: "shippingbox.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(16)
                    .background(LinearGradient(colors: [purple, Color(red: 0.37, green: 0.18, blue: 0.76)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 15)).foregroundStyle(.white)
            }
            .buttonStyle(.plain).disabled(sourceURL == nil)
            .opacity(sourceURL == nil ? 0.45 : 1)

            Button(action: generateXML) {
                Label("إنشاء dlclist.xml", systemImage: "doc.badge.gearshape")
                    .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(14)
                    .background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 15))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain).disabled(names.isEmpty)
            .opacity(names.isEmpty ? 0.4 : 1)
        }
    }

    private func outputCard(_ folder: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("الملفات الجاهزة", icon: "checkmark.seal.fill")
            Text(folder.lastPathComponent).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            Text("تم فك الأرشيف إلى مجلد مستقل. الأصل محفوظ كما هو.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
            ShareLink(item: folder) {
                Label("سحب / مشاركة المجلد إلى «الملفات»", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(13)
                    .background(purple.opacity(0.24)).clipShape(RoundedRectangle(cornerRadius: 13))
                    .foregroundStyle(.white)
            }
        }
        .padding(16).panel()
    }

    private func xmlShareCard(_ url: URL) -> some View {
        ShareLink(item: url) {
            Label("مشاركة ملف dlclist.xml", systemImage: "arrow.up.doc.fill")
                .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(14)
                .background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
        }
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? .red : purple)
            Text(status).font(.caption).foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var footer: some View {
        Text("تنبيه: تجهيز الملفات لا يحوّل مودات PC إلى صيغة PS4 تلقائياً، ولا يثبتها على الجهاز.")
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            .multilineTextAlignment(.center).padding(.horizontal, 8)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).foregroundStyle(.white)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let pickedURL = urls.first else {
                fail("ما تم اختيار أي ملف.")
                return
            }
            isBusy = true
            progressText = "جاري استيراد الملف إلى التطبيق..."
            Task {
                do {
                    let importedURL = try await Task.detached(priority: .userInitiated) {
                        try Self.copyPickedItemIntoAppStorage(pickedURL)
                    }.value
                    sourceURL = importedURL
                    selectedFileName = pickedURL.lastPathComponent
                    status = "تم استيراد الملف وحفظ نسخة داخل التطبيق. صار جاهز للمعالجة."
                    isError = false
                } catch {
                    fail("تعذر استيراد الملف: \(error.localizedDescription)")
                }
                isBusy = false
            }
        case .failure(let error):
            fail("تعذر اختيار الملف: \(error.localizedDescription)")
        }
    }

    private static func copyPickedItemIntoAppStorage(_ source: URL) throws -> URL {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { source.stopAccessingSecurityScopedResource() }
        }

        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        let imports = appSupport.appendingPathComponent("GTAConverter/Imports", isDirectory: true)
        try fm.createDirectory(at: imports, withIntermediateDirectories: true)
        let destinationRoot = imports.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        var copiedURL: URL?
        var coordinationError: NSError?
        var copyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readableURL in
            do {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: readableURL.path, isDirectory: &isDirectory) else {
                    throw ImportError.folderRead
                }
                if isDirectory.boolValue {
                    try Self.copyFolderSafely(from: readableURL, to: destinationRoot)
                    copiedURL = destinationRoot
                } else {
                    let destination = destinationRoot.appendingPathComponent(source.lastPathComponent)
                    try fm.copyItem(at: readableURL, to: destination)
                    copiedURL = destination
                }
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard let copiedURL else { throw ImportError.folderRead }
        return copiedURL
    }

    private func downloadFromLink() {
        guard let url = URL(string: directURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            fail("الرابط غير صحيح. استخدم رابط http أو https مباشر للملف.")
            return
        }
        Task {
            isBusy = true
            progressText = "تحميل الملف..."
            defer { isBusy = false }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 180
                request.setValue("PS4TOOLS-MOBILE-iOS", forHTTPHeaderField: "User-Agent")
                let (temporary, response) = try await URLSession.shared.download(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw ImportError.http(http.statusCode)
                }
                let ext = url.pathExtension.isEmpty ? "zip" : url.pathExtension
                guard ["zip", "rar"].contains(ext.lowercased()) else {
                    throw ImportError.unsupported
                }
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("GTA-Download-\(UUID().uuidString).\(ext)")
                try FileManager.default.moveItem(at: temporary, to: destination)
                sourceURL = destination
                selectedFileName = destination.lastPathComponent
                status = "اكتمل التحميل. اضغط «فك الملفات»."
                isError = false
            } catch {
                fail("فشل التحميل: \(error.localizedDescription)")
            }
        }
    }

    private func processSource() {
        guard let sourceURL else { return }
        Task {
            isBusy = true
            progressText = "نسخ وفك الملفات بأمان..."
            defer { isBusy = false }
            do {
                let root = FileManager.default.temporaryDirectory
                    .appendingPathComponent("GTA-Prepared-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    try Self.copyFolderSafely(from: sourceURL, to: root)
                } else {
                    let reader = try await ArchiveReader(reading: .fileURL(sourceURL))
                    var totalBytes: Int64 = 0
                    var count = 0
                    for try await item in reader {
                        let raw = item.entry.path
                        let relative = try Self.safeRelativePath(raw)
                        let destination = root.appendingPathComponent(relative)
                        if raw.hasSuffix("/") {
                            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                            continue
                        }
                        let data = Data(item.bytes)
                        totalBytes += Int64(data.count)
                        count += 1
                        guard totalBytes <= 1_500_000_000, count <= 20_000 else {
                            throw ImportError.archiveTooLarge
                        }
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                                withIntermediateDirectories: true)
                        try data.write(to: destination, options: .atomic)
                    }
                    await reader.close()
                    guard count > 0 else { throw ImportError.emptyArchive }
                }
                outputFolder = root
                status = "اكتمل فك الملفات. تم الاحتفاظ بالأصل وإنشاء نسخة عمل مستقلة."
                isError = false
            } catch {
                fail("تعذر تجهيز الأرشيف: \(error.localizedDescription)")
            }
        }
    }

    private static func safeRelativePath(_ raw: String) throws -> String {
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty, !normalized.hasPrefix("/"),
              !parts.contains(".."), !parts.contains(".") else {
            throw ImportError.unsafePath
        }
        return parts.map(String.init).joined(separator: "/")
    }

    private static func copyFolderSafely(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles]) else {
            throw ImportError.folderRead
        }
        var count = 0
        for case let item as URL in enumerator {
            let relative = String(item.path.dropFirst(source.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let safe = try Self.safeRelativePath(relative)
            let target = destination.appendingPathComponent(safe)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                count += 1
                guard count <= 20_000 else { throw ImportError.archiveTooLarge }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    private func generateXML() {
        guard !names.isEmpty else { return }
        let entries = names.map { "        <Item>/data/orbx/gta/rpf/dlc_addon/\($0)/</Item>" }
            .joined(separator: "\n")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <SMandatoryPacksData>
          <Paths>
        \(entries)
          </Paths>
        </SMandatoryPacksData>
        """
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dlclist.xml")
            try xml.write(to: url, atomically: true, encoding: .utf8)
            generatedURL = url
            status = "تم إنشاء dlclist.xml بعدد \(names.count) حزمة."
            isError = false
        } catch { fail("فشل إنشاء XML: \(error.localizedDescription)") }
    }

    private func fail(_ message: String) {
        status = message
        isError = true
    }

    private enum ImportError: LocalizedError {
        case http(Int), unsupported, archiveTooLarge, emptyArchive, unsafePath, folderRead
        var errorDescription: String? {
            switch self {
            case .http(let code): return "استجابة الموقع: HTTP \(code)"
            case .unsupported: return "الرابط يجب أن ينتهي بملف ZIP أو RAR."
            case .archiveTooLarge: return "الأرشيف أكبر من الحدود الآمنة أو يحتوي ملفات كثيرة."
            case .emptyArchive: return "الأرشيف فارغ أو تنسيقه غير مدعوم."
            case .unsafePath: return "الأرشيف يحتوي مسار ملفات غير آمن وتم إيقاف الفك."
            case .folderRead: return "تعذرت قراءة محتويات المجلد."
            }
        }
    }
}

private extension View {
    func panel() -> some View {
        self.background(Color.white.opacity(0.065))
            .clipShape(RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.055)))
    }
}

private extension UTType {
    static let rar = UTType(filenameExtension: "rar") ?? .archive
}
