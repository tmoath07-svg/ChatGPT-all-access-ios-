import SwiftUI
import UniformTypeIdentifiers
import SwiftArchive

/// Imports a FiveM resource archive (ZIP/RAR), safely extracts it, and analyzes its structure.
struct FiveMStudioView: View {
    @State private var showingFilePicker = false
    @State private var report: ModAnalysisReport?
    @State private var status = "اختر ملف ZIP أو RAR لمورد FiveM."
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var importedName = ""

    private let workflowURL = URL(string: "https://github.com/tmoath07-svg/ChatGPT-all-access-ios-/actions/workflows/convert-pc-to-ps4.yml")!

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.025, blue: 0.065).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "car.side.3.fill").font(.system(size: 34)).foregroundStyle(.purple)
                        Text("FiveM Resource Studio").font(.title2.bold()).foregroundStyle(.white)
                        Text("استورد ZIP أو RAR أو أي ملف مورد FiveM منفرد مثل YFT وYTD وMETA وLua. يفك الأرشيف أو يحفظ الملف محلياً ثم يفحص البنية والاعتماديات الظاهرة.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))

                    Button {
                        errorText = nil
                        showingFilePicker = true
                    } label: {
                        Label(isBusy ? "جاري الاستيراد والفحص..." : "اختيار ملف أو أرشيف FiveM", systemImage: "doc.zipper")
                            .font(.headline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(15)
                            .background(Color.purple.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                    .disabled(isBusy)

                    Text(importedName.isEmpty ? status : "\(status)\nالملف: \(importedName)")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                    if let errorText {
                        Text(errorText).font(.caption).foregroundStyle(.red)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.red.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if let report {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("تقرير المورد").font(.headline.bold()).foregroundStyle(.white)
                                Spacer()
                                Text(report.isFiveMVehicleResource ? "مورد مركبة مكتشف" : "يحتاج مراجعة")
                                    .font(.caption2.bold())
                                    .foregroundStyle(report.isFiveMVehicleResource ? .green : .orange)
                            }
                            metric("الملفات", value: "\(report.fileCount)")
                            metric("الحجم", value: ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))
                            metric("YFT / YTD", value: "\(report.yftFiles.count) / \(report.ytdFiles.count)")
                            metric("ملفات META", value: "\(report.vehicleMetaFiles.count)")
                            metric("Manifest", value: "\(report.manifestFiles.count)")
                            Text(report.reportText)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.78))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12).background(.black.opacity(0.25))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(15).background(.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Link(destination: workflowURL) {
                        Label("فتح سير عمل تحويل FiveM إلى DLC", systemImage: "arrow.up.right.square")
                            .font(.headline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(15)
                            .background(Color.orange.opacity(0.78))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                    }

                    Text("تنبيه: الفحص المحلي لا يحوّل المورد إلى PS4. ملفات Lua وNUI واعتماديات السيرفر لا تتحول تلقائياً إلى DLC. الملفات المدعومة فقط يمكن تمريرها لمحرك التحويل، ويجب فحص الناتج قبل نقله.")
                        .font(.caption).foregroundStyle(.orange.opacity(0.9))
                        .padding(12).background(.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding(16)
            }
        }
        .navigationTitle("FiveM Studio")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(.white)
        }.font(.caption).padding(.vertical, 2)
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorText = "تعذر اختيار الملف: \(error.localizedDescription)"
            status = "لم يتم استيراد أي ملف."
        case .success(let urls):
            guard let source = urls.first else {
                status = "لم يتم اختيار ملف."
                return
            }
            let ext = source.pathExtension.lowercased()
            if ext == "zip" || ext == "rar" {
                importAndAnalyze(source)
            } else {
                importSingleFileAndAnalyze(source)
            }
        }
    }

    private func importSingleFileAndAnalyze(_ source: URL) {
        isBusy = true
        errorText = nil
        report = nil
        importedName = source.lastPathComponent
        status = "يتم استيراد ملف المورد المفرد..."
        Task {
            var staging: URL?
            do {
                let copy = try await Task.detached(priority: .userInitiated) {
                    try FileImportService.importItem(from: source, category: "FiveMFiles")
                }.value
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let parent = documents.appendingPathComponent("GTA Converter/FiveM/Extracted", isDirectory: true)
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                let destination = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                staging = destination
                let target = destination.appendingPathComponent(copy.lastPathComponent)
                try FileManager.default.copyItem(at: copy, to: target)
                let result = try await Task.detached(priority: .userInitiated) {
                    try ModAnalyzer.analyze(at: destination)
                }.value
                report = result
                status = "تم استيراد الملف وفحصه محلياً. هذا جرد للملف وليس تحويلاً إلى PS4."
                staging = nil
            } catch {
                if let staging { try? FileManager.default.removeItem(at: staging) }
                errorText = error.localizedDescription
                status = "تعذر استيراد أو فحص الملف المفرد."
            }
            isBusy = false
        }
    }

    private func importAndAnalyze(_ source: URL) {
        isBusy = true
        errorText = nil
        report = nil
        importedName = source.lastPathComponent
        status = "يتم حفظ الأرشيف داخل INRPF..."
        Task {
            var extractionRoot: URL?
            do {
                let copy = try await Task.detached(priority: .userInitiated) {
                    try FileImportService.importItem(from: source, category: "FiveMArchives")
                }.value
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let parent = documents.appendingPathComponent("GTA Converter/FiveM/Extracted", isDirectory: true)
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                let destination = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                extractionRoot = destination
                status = "تم الاستيراد. يتم فك الأرشيف وفحصه..."
                try await Self.extractArchive(copy, to: destination)
                let result = try await Task.detached(priority: .userInitiated) {
                    try ModAnalyzer.analyze(at: destination)
                }.value
                report = result
                status = result.isFiveMVehicleResource
                    ? "اكتمل الفحص وتم التعرف على مورد مركبة FiveM."
                    : "اكتمل الفحص، لكن بنية المورد تحتاج مراجعة. راجع التقرير."
                extractionRoot = nil
            } catch {
                if let extractionRoot { try? FileManager.default.removeItem(at: extractionRoot) }
                errorText = error.localizedDescription
                status = "تعذر استيراد أو فك أو فحص الملف."
            }
            isBusy = false
        }
    }

    private static func extractArchive(_ archiveURL: URL, to destination: URL) async throws {
        let reader = try await ArchiveReader(reading: .fileURL(archiveURL))
        var totalBytes: Int64 = 0
        var fileCount = 0
        do {
            while let entry = try await reader.nextEntry() {
                let raw = entry.path.replacingOccurrences(of: "\\", with: "/")
                let parts = raw.split(separator: "/", omittingEmptySubsequences: true)
                guard !parts.isEmpty, !raw.hasPrefix("/"), !parts.contains(".."), !parts.contains(".") else {
                    throw NSError(domain: "INRPF.FiveMImport", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "الأرشيف يحتوي مساراً داخلياً غير آمن: \(raw)"])
                }
                let relative = parts.map(String.init).joined(separator: "/")
                let target = destination.appendingPathComponent(relative, isDirectory: entry.fileType == .directory)
                switch entry.fileType {
                case .directory:
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                case .regular:
                    if entry.hardlinkTarget != nil {
                        try await reader.skipData()
                        continue
                    }
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    var existingIsDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: target.path, isDirectory: &existingIsDirectory) {
                        throw NSError(domain: "INRPF.FiveMImport", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "تعارض في مسار الأرشيف: \(relative)"])
                    }
                    guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
                        throw NSError(domain: "INRPF.FiveMImport", code: 3,
                                      userInfo: [NSLocalizedDescriptionKey: "تعذر إنشاء الملف: \(relative)"])
                    }
                    let output = try FileHandle(forWritingTo: target)
                    do {
                        while true {
                            let chunk = try await reader.readData(maxLength: 1024 * 1024)
                            if chunk.isEmpty { break }
                            totalBytes += Int64(chunk.count)
                            guard totalBytes <= 1_500_000_000, fileCount < 20_000 else {
                                throw NSError(domain: "INRPF.FiveMImport", code: 4,
                                              userInfo: [NSLocalizedDescriptionKey: "الأرشيف تجاوز الحد الآمن (1.5GB أو 20,000 ملف)."])
                            }
                            try output.write(contentsOf: Data(chunk))
                        }
                        try output.close()
                    } catch {
                        try? output.close()
                        throw error
                    }
                    fileCount += 1
                case .symlink:
                    try await reader.skipData()
                default:
                    try await reader.skipData()
                }
            }
            await reader.close()
        } catch {
            await reader.close()
            throw error
        }
        guard fileCount > 0 else {
            throw NSError(domain: "INRPF.FiveMImport", code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "الأرشيف فارغ أو لا يحتوي ملفات قابلة للاستخراج."])
        }
    }
}
