import SwiftUI
import WebKit
import PhotosUI
import Combine

// MARK: - Shared app background

struct GTAAppBackground: View {
    @AppStorage("gta_background_color") private var backgroundColor = "midnight"
    @AppStorage("gta_custom_background_path") private var customPath = ""

    private var color: Color {
        switch backgroundColor {
        case "black": return Color.black
        case "navy": return Color(red: 0.015, green: 0.045, blue: 0.12)
        case "purple": return Color(red: 0.10, green: 0.035, blue: 0.19)
        case "graphite": return Color(red: 0.075, green: 0.08, blue: 0.11)
        default: return Color(red: 0.035, green: 0.025, blue: 0.065)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                color.ignoresSafeArea()
                if !customPath.isEmpty, let image = UIImage(contentsOfFile: customPath) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay(Color.black.opacity(0.58))
                        .ignoresSafeArea()
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Motion blur entrance

private struct GTAMotionEntrance: ViewModifier {
    @AppStorage("gta_motion_blur_enabled") private var enabled = true
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0.72)
            .blur(radius: enabled && !appeared ? 13 : 0)
            .scaleEffect(appeared ? 1 : 0.985)
            .animation(.spring(response: 0.48, dampingFraction: 0.86), value: appeared)
            .onAppear { appeared = true }
    }
}

private extension View {
    func gtaMotionEntrance() -> some View { modifier(GTAMotionEntrance()) }
}

// MARK: - Download center

struct GTADownloadRecord: Identifiable, Codable {
    var id: UUID
    var sourceURL: String
    var fileName: String
    var progress: Double
    var status: String
    var localPath: String?
    var receivedBytes: Int64
    var expectedBytes: Int64
    var createdAt: Date
}

final class GTADownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = GTADownloadManager()
    @Published private(set) var items: [GTADownloadRecord] = []

    private let storageKey = "gta_download_history_v1"
    private var taskIDs: [Int: UUID] = [:]
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([GTADownloadRecord].self, from: data) {
            items = saved.map { item in
                var value = item
                if value.status == "جاري التحميل" { value.status = "توقف التحميل عند إغلاق التطبيق" }
                return value
            }
            persist()
        }
    }

    func startDownload(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return }
        var request = URLRequest(url: url)
        request.setValue("GTAConverter-iOS", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        let record = GTADownloadRecord(
            id: UUID(),
            sourceURL: url.absoluteString,
            fileName: url.lastPathComponent.isEmpty ? "GTA-Mod-Download" : url.lastPathComponent,
            progress: 0,
            status: "جاري التحميل",
            localPath: nil,
            receivedBytes: 0,
            expectedBytes: 0,
            createdAt: Date()
        )
        items.insert(record, at: 0)
        taskIDs[task.taskIdentifier] = record.id
        persist()
        task.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = taskIDs[downloadTask.taskIdentifier],
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].receivedBytes = totalBytesWritten
        items[index].expectedBytes = totalBytesExpectedToWrite
        if totalBytesExpectedToWrite > 0 {
            items[index].progress = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
        persist()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = taskIDs[downloadTask.taskIdentifier],
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        do {
            let fm = FileManager.default
            let documents = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let library = documents.appendingPathComponent("GTA Converter/Mods", isDirectory: true)
            try fm.createDirectory(at: library, withIntermediateDirectories: true)
            let suggested = downloadTask.response?.suggestedFilename ?? items[index].fileName
            let cleaned = suggested.replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
            var destination = library.appendingPathComponent(cleaned)
            if fm.fileExists(atPath: destination.path) {
                destination = library.appendingPathComponent(UUID().uuidString + "-" + cleaned)
            }
            try fm.moveItem(at: location, to: destination)
            items[index].fileName = destination.lastPathComponent
            items[index].localPath = destination.path
            items[index].progress = 1
            items[index].status = "اكتمل وحُفظ في مكتبة المودات"
            GTATransferHistoryStore.record(title: "تنزيل مود", detail: destination.lastPathComponent)
            if items[index].expectedBytes <= 0,
               let savedSize = (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                items[index].expectedBytes = Int64(savedSize)
            }
        } catch {
            items[index].status = "فشل حفظ الملف: " + error.localizedDescription
        }
        taskIDs.removeValue(forKey: downloadTask.taskIdentifier)
        persist()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = taskIDs[task.taskIdentifier],
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let error, items[index].status == "جاري التحميل" {
            items[index].status = "فشل التحميل: " + error.localizedDescription
        }
        taskIDs.removeValue(forKey: task.taskIdentifier)
        persist()
    }

    func remove(_ item: GTADownloadRecord) {
        if let path = item.localPath { try? FileManager.default.removeItem(atPath: path) }
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - In-app mod browser

struct GTAModBrowserView: View {
    @State private var address = "https://www.gta5-mods.com/vehicles"
    @State private var searchQuery = ""
    @State private var searchCategory = "vehicles"
    @State private var browserID = UUID()
    @State private var showSearchNotice = false
    @StateObject private var downloads = GTADownloadManager.shared

    private let shortcuts: [(String, String, String)] = [
        ("مركبات", "car.side.fill", "https://www.gta5-mods.com/vehicles"),
        ("خرائط", "map.fill", "https://www.gta5-mods.com/maps"),
        ("شخصيات", "person.fill", "https://www.gta5-mods.com/player")
    ]

    private var validURL: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
        return url
    }

    private var isArchiveLink: Bool {
        guard let url = validURL else { return false }
        return ["zip", "rar"].contains(url.pathExtension.lowercased())
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(.purple)
                TextField("رابط موقع أو مود", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .environment(.layoutDirection, .leftToRight)
                    .foregroundStyle(.white)
                Button {
                    if validURL != nil { browserID = UUID() }
                } label: {
                    Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundStyle(.purple)
                }
            }
            .padding(12)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .padding(.horizontal, 12)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("ابحث عن مود مركبة أو خريطة أو شخصية", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(performSearch)
                        .foregroundStyle(.white)
                    Button(action: performSearch) {
                        Label("بحث", systemImage: "magnifyingglass")
                            .font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 9)
                            .background(.purple.opacity(0.75)).clipShape(Capsule()).foregroundStyle(.white)
                    }
                }
                .padding(11).background(.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)

                Picker("التصنيف", selection: $searchCategory) {
                    Text("مركبات").tag("vehicles")
                    Text("خرائط").tag("maps")
                    Text("شخصيات").tag("player")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(shortcuts.indices, id: \.self) { index in
                        let item = shortcuts[index]
                        Button {
                            address = item.2
                            browserID = UUID()
                        } label: {
                            Label(item.0, systemImage: item.1)
                                .font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(.white.opacity(0.08))
                                .clipShape(Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }.padding(.horizontal, 12)
            }

            if let url = validURL {
                BrowserWebView(url: url, manager: downloads)
                    .id(browserID)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 8)
            } else {
                ContentUnavailablePlaceholder()
            }

            HStack(spacing: 8) {
                Button {
                    guard let url = validURL else { return }
                    downloads.startDownload(url)
                } label: {
                    Label("تنزيل ملف ZIP / RAR", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(12)
                        .background(Color.purple.opacity(isArchiveLink ? 0.8 : 0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }
                .disabled(!isArchiveLink)
                NavigationLink(destination: GTADownloadsView()) {
                    Label("التنزيلات", systemImage: "tray.and.arrow.down.fill")
                        .font(.subheadline.bold()).padding(12)
                        .background(.white.opacity(0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }
            }.padding(.horizontal, 12).padding(.bottom, 8)
        }
        .background(GTAAppBackground())
        .navigationTitle("متصفح المودات")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .alert("البحث غير متاح", isPresented: $showSearchNotice) {
            Button("حسناً", role: .cancel) { }
        } message: {
            Text("البحث هنا مخصص لمودات المركبات والخرائط والشخصيات.")
        }
        .gtaMotionEntrance()
    }

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let blockedTerms = ["gun", "guns", "weapon", "weapons", "rifle", "pistol", "ammo", "firearm",
                            "سلاح", "اسلحة", "أسلحة", "مسدس", "بندقية", "رشاش", "ذخيرة"]
        let normalized = query.lowercased()
        if blockedTerms.contains(where: { normalized.localizedCaseInsensitiveContains($0) }) {
            showSearchNotice = true
            return
        }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        address = "https://www.google.com/search?q=site%3Agta5-mods.com%2F\(searchCategory)+\(encoded)"
        browserID = UUID()
    }
}

private struct ContentUnavailablePlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "link.badge.plus").font(.largeTitle).foregroundStyle(.purple)
            Text("اكتب رابط صحيح يبدأ بـ http أو https").foregroundStyle(.white.opacity(0.7))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let url: URL
    let manager: GTADownloadManager

    func makeCoordinator() -> Coordinator { Coordinator(manager: manager) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.035, green: 0.025, blue: 0.065, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let manager: GTADownloadManager
        init(manager: GTADownloadManager) { self.manager = manager }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let ext = url.pathExtension.lowercased()
            if ["zip", "rar"].contains(ext) {
                manager.startDownload(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - Downloads list

struct GTADownloadsView: View {
    @StateObject private var manager = GTADownloadManager.shared

    var body: some View {
        ZStack {
            GTAAppBackground()
            if manager.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc").font(.system(size: 42)).foregroundStyle(.purple)
                    Text("ما فيه تنزيلات للحين").foregroundStyle(.white.opacity(0.7))
                }
            } else {
                List {
                    ForEach(manager.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: item.status.contains("اكتمل") ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                    .foregroundStyle(item.status.contains("اكتمل") ? .green : .purple)
                                Text(item.fileName).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
                            }
                            ProgressView(value: item.progress).tint(.purple)
                            HStack {
                                Text(item.status).lineLimit(2)
                                Spacer()
                                Text(item.progress.formatted(.percent.precision(.fractionLength(0))))
                            }.font(.caption2).foregroundStyle(.white.opacity(0.65))
                            if let path = item.localPath {
                                ShareLink(item: URL(fileURLWithPath: path)) {
                                    Label("مشاركة الملف", systemImage: "square.and.arrow.up")
                                        .font(.caption.bold()).foregroundStyle(.purple)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(Color.white.opacity(0.055))
                        .contextMenu {
                            Button(role: .destructive) { manager.remove(item) } label: {
                                Label("حذف", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
        }
        .navigationTitle("التنزيلات")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .gtaMotionEntrance()
    }
}

 // MARK: - Persistent transfer history

struct GTATransferEvent: Identifiable, Codable {
    var id: UUID
    var title: String
    var detail: String
    var date: Date
}

enum GTATransferHistoryStore {
    private static let key = "gta_transfer_events_v1"

    static func record(title: String, detail: String) {
        var events = load()
        events.insert(GTATransferEvent(id: UUID(), title: title, detail: detail, date: Date()), at: 0)
        if events.count > 250 { events = Array(events.prefix(250)) }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> [GTATransferEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let events = try? JSONDecoder().decode([GTATransferEvent].self, from: data) else { return [] }
        return events.sorted { $0.date > $1.date }
    }
}

// MARK: - Mods library and activity history

struct GTAModsLibraryView: View {
    @State private var files: [URL] = []
    @State private var query = ""

    private var root: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTA Converter", isDirectory: true)
    }

    private var visibleFiles: [URL] {
        files.filter { query.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            GTAAppBackground()
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
                    TextField("ابحث عن مود أو ملف", text: $query).foregroundStyle(.white)
                }.padding(12).background(.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 14)

                HStack {
                    Label("\(files.count) ملف ومجلد", systemImage: "square.grid.2x2.fill")
                    Spacer()
                    Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                }
                .font(.caption.bold()).foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 16)

                List {
                    ForEach(visibleFiles, id: \.path) { url in
                        HStack(spacing: 10) {
                            Image(systemName: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true ? "folder.fill" : "shippingbox.fill")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(url.lastPathComponent).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                                Text(fileInfo(url)).font(.caption2).foregroundStyle(.white.opacity(0.48))
                            }
                            Spacer()
                            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                                ShareLink(item: url) { Image(systemName: "square.and.arrow.up").foregroundStyle(.white.opacity(0.7)) }
                            }
                        }.listRowBackground(Color.white.opacity(0.05))
                    }
                }.scrollContentBackground(.hidden).listStyle(.plain)
            }
        }
        .navigationTitle("مكتبة المودات")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .environment(\.layoutDirection, .rightToLeft)
        .gtaMotionEntrance()
    }

    private func refresh() {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let folders = ["Mods", "Imports", "Ready"].map { root.appendingPathComponent($0, isDirectory: true) }
        files = folders.flatMap { folder in
            (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
    }

    private func fileInfo(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true { return "مجلد" }
        return ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
    }
}

struct GTATransferHistoryView: View {
    @State private var records: [(String, String, Date)] = []

    var body: some View {
        ZStack {
            GTAAppBackground()
            List {
                ForEach(records.indices, id: \.self) { index in
                    let record = records[index]
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.0).font(.subheadline.bold()).foregroundStyle(.white)
                        Text(record.1).font(.caption).foregroundStyle(.white.opacity(0.6))
                        Text(record.2.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.purple)
                    }.padding(.vertical, 5).listRowBackground(Color.white.opacity(0.05))
                }
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if records.isEmpty {
                    Text("سجل العمليات بيظهر هنا بعد استيراد الملفات وتجهيزها.")
                        .font(.caption).foregroundStyle(.white.opacity(0.65)).padding()
                }
            }
        }
        .navigationTitle("سجل العمليات")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .environment(\.layoutDirection, .rightToLeft)
        .gtaMotionEntrance()
    }

    private func load() {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTA Converter", isDirectory: true)
        var found: [(String, String, Date)] = []
        for folderName in ["Imports", "Mods", "Ready"] {
            let folder = root.appendingPathComponent(folderName, isDirectory: true)
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
            for url in urls {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                found.append((url.lastPathComponent, folderName, date))
            }
        }
        let savedEvents = GTATransferHistoryStore.load().map { ($0.title, $0.detail, $0.date) }
        records = (savedEvents + found).sorted { $0.2 > $1.2 }
    }
}

// MARK: - Appearance settings

struct GTAAppearanceSettingsView: View {
    @AppStorage("gta_accent_color") private var accent = "purple"
    @AppStorage("gta_cover_style") private var cover = "neon"
    @AppStorage("gta_background_color") private var background = "midnight"
    @AppStorage("gta_motion_blur_enabled") private var motionBlur = true
    @AppStorage("gta_custom_background_path") private var customPath = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var message = ""

    private let accents: [(String, String)] = [
        ("purple", "بنفسجي"), ("blue", "أزرق"), ("green", "أخضر"),
        ("orange", "برتقالي"), ("red", "أحمر")
    ]
    private let backgrounds: [(String, String)] = [
        ("midnight", "ليلي"), ("black", "أسود"), ("navy", "كحلي"),
        ("purple", "بنفسجي داكن"), ("graphite", "رمادي فحمي")
    ]

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("لون الواجهة", icon: "paintpalette.fill") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                            ForEach(accents.indices, id: \.self) { index in
                                let option = accents[index]
                                Button { accent = option.0 } label: {
                                    HStack {
                                        Circle().fill(color(option.0)).frame(width: 15, height: 15)
                                        Text(option.1).font(.subheadline.bold())
                                        Spacer()
                                        if accent == option.0 { Image(systemName: "checkmark.circle.fill") }
                                    }.foregroundStyle(.white).padding(12)
                                        .background(.white.opacity(accent == option.0 ? 0.15 : 0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 11))
                                }
                            }
                        }
                    }

                    section("خلفية التطبيق", icon: "photo.fill") {
                        ForEach(backgrounds.indices, id: \.self) { index in
                            let option = backgrounds[index]
                            Button { background = option.0; customPath = "" } label: {
                                HStack {
                                    Text(option.1).foregroundStyle(.white)
                                    Spacer()
                                    if background == option.0 && customPath.isEmpty { Image(systemName: "checkmark").foregroundStyle(.purple) }
                                }.padding(11).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("اختيار صورة من الصور", systemImage: "photo.badge.plus")
                                .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(12)
                                .background(.purple.opacity(0.28)).clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                        if !customPath.isEmpty {
                            Button(role: .destructive) {
                                customPath = ""
                                message = "تم الرجوع للخلفية الافتراضية."
                            } label: { Label("إزالة الخلفية المخصصة", systemImage: "trash") }
                                .foregroundStyle(.red)
                        }
                    }

                    section("الحركة", icon: "sparkles") {
                        Toggle(isOn: $motionBlur) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Motion Blur").foregroundStyle(.white)
                                Text("تمويه وانتقال ناعم عند فتح صفحات الأدوات").font(.caption).foregroundStyle(.white.opacity(0.55))
                            }
                        }.tint(.purple)
                    }

                    section("غلاف التطبيق", icon: "app.fill") {
                        Picker("نمط الغلاف", selection: $cover) {
                            Text("نيون").tag("neon")
                            Text("داكن").tag("dark")
                            Text("بسيط").tag("minimal")
                        }.pickerStyle(.segmented)
                        Text("الأيقونة الخارجية تُحدد وقت بناء التطبيق. تغييرها من داخل التطبيق يحتاج تجهيز أيقونات بديلة في حزمة iOS أولاً.")
                            .font(.caption).foregroundStyle(.white.opacity(0.58))
                    }

                    if !message.isEmpty {
                        Text(message).font(.caption).foregroundStyle(.green)
                    }
                }.padding(16)
            }
        }
        .navigationTitle("تخصيص التطبيق")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .onChange(of: selectedPhoto) { newValue in
            guard let newValue else { return }
            Task {
                do {
                    guard let data = try await newValue.loadTransferable(type: Data.self),
                          let image = UIImage(data: data),
                          let jpeg = image.jpegData(compressionQuality: 0.88) else {
                        message = "تعذر قراءة الصورة المختارة."
                        return
                    }
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let folder = docs.appendingPathComponent("GTA Converter", isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let destination = folder.appendingPathComponent("custom-background.jpg")
                    try jpeg.write(to: destination, options: .atomic)
                    customPath = destination.path
                    message = "تم تطبيق الخلفية المخصصة."
                } catch {
                    message = "تعذر حفظ الخلفية: " + error.localizedDescription
                }
            }
        }
        .gtaMotionEntrance()
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.white)
            content()
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 17))
    }

    private func color(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        default: return .purple
        }
    }
}
