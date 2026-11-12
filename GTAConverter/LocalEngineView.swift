import SwiftUI
import UniformTypeIdentifiers

struct LocalEngineView: View {
    let initialFolder: URL?

    @State private var sourceFolder: URL?
    @State private var outputFile: URL?
    @State private var report = ""
    @State private var errorText = ""
    @State private var isBusy = false
    @State private var showingFolderPicker = false
    @State private var showingRPFPicker = false
    @State private var showingResourcePicker = false
    @State private var showingYTDPicker = false
    @State private var extractedTextureFolder: URL?
    @State private var convertedResourceURL: URL?

    init(initialFolder: URL? = nil) {
        self.initialFolder = initialFolder
        _sourceFolder = State(initialValue: initialFolder)
    }

    private let purple = Color(red: 0.57, green: 0.30, blue: 0.98)

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("GTA LOCAL ENGINE", systemImage: "cpu.fill")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(1.2).foregroundStyle(purple)
                        Text("محرك الملفات المحلي").font(.title2.bold()).foregroundStyle(.white)
                        Text(LocalEngineBridge.version)
                            .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.55))
                        Text("إنشاء وفحص RPF7 وتحويل بعض موارد RSC7 محلياً داخل الجهاز، بدون إرسال الملفات إلى خادم.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.13)))

                    VStack(alignment: .leading, spacing: 10) {
                        Label("مجلد الملفات المصدرية", systemImage: "folder.fill")
                            .font(.headline).foregroundStyle(.white)
                        Text(sourceFolder?.lastPathComponent ?? "لم يتم اختيار مجلد")
                            .font(.caption).foregroundStyle(.white.opacity(0.62))
                        Button { showingFolderPicker = true } label: {
                            Label("اختيار مجلد", systemImage: "folder.badge.plus")
                                .frame(maxWidth: .infinity).padding(13)
                                .background(.white.opacity(0.09))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16).localEnginePanel()

                    Button(action: buildRPF) {
                        HStack {
                            if isBusy { ProgressView().tint(.white) }
                            Label(isBusy ? "جاري بناء RPF7..." : "بناء أرشيف RPF7 محلي", systemImage: "shippingbox.fill")
                        }
                        .font(.headline.bold()).frame(maxWidth: .infinity).padding(15)
                        .background(LinearGradient(colors: [purple, purple.opacity(0.65)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(sourceFolder == nil || isBusy)
                    .opacity(sourceFolder == nil || isBusy ? 0.45 : 1)

                    Button { showingRPFPicker = true } label: {
                        Label("فحص ملف RPF موجود", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).disabled(isBusy)

                    Button { showingResourcePicker = true } label: {
                        Label("تحويل مورد Y* إلى O* محلياً", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).disabled(isBusy)

                    Button { showingYTDPicker = true } label: {
                        Label("استخراج خامات YTD إلى DDS", systemImage: "photo.stack")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).disabled(isBusy)

                    if let outputFile {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("تم إنشاء الملف وفحص بنيته", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(outputFile.lastPathComponent).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7))
                            ShareLink(item: outputFile) {
                                Label("مشاركة أرشيف RPF7", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(13)
                                    .background(.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                            }
                        }
                        .padding(15).localEnginePanel()
                    }

                    if let convertedResourceURL {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("تم إنشاء المورد المحوّل", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(convertedResourceURL.lastPathComponent)
                                .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7))
                            ShareLink(item: convertedResourceURL) {
                                Label("مشاركة المورد المحوّل", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(13)
                                    .background(.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                            }
                        }
                        .padding(15).localEnginePanel()
                    }

                    if let extractedTextureFolder {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("تم استخراج الخامات", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(extractedTextureFolder.lastPathComponent)
                                .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7))
                            ShareLink(item: extractedTextureFolder) {
                                Label("مشاركة مجلد DDS", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(13)
                                    .background(.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                            }
                        }
                        .padding(15).localEnginePanel()
                    }

                    if !report.isEmpty {
                        Text(report).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.78))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).background(.black.opacity(0.22))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                    if !errorText.isEmpty {
                        Text(errorText).font(.caption).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13).background(.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Label("حدود المرحلة الحالية", systemImage: "info.circle.fill")
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                        Text("هذا المحرك ينشئ حاوية RPF7 عامة ويفحص جدولها. تحويل الموارد البنيوية واستخراج YTD إلى DDS متاحان. بناء OTD بضغط PS4 ومحرك ragebuilder وتجميع DLC النهائي لم تكتمل بعد. حد المعالجة 512MB. لا تعتبر الناتج حزمة PS4 جاهزة.")
                            .font(.caption).foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(14).background(.orange.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(16)
            }
        }
        .navigationTitle("المحرك المحلي")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .fileImporter(isPresented: $showingFolderPicker,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): sourceFolder = urls.first
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showingRPFPicker,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                inspect(url)
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showingResourcePicker,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                convertResource(url)
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showingYTDPicker,
                      allowedContentTypes: [.item],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                extractYTD(url)
            case .failure(let error): errorText = error.localizedDescription
            }
        }
    }

    private func buildRPF() {
        guard let folder = sourceFolder else { return }
        let access = folder.startAccessingSecurityScopedResource()
        isBusy = true
        errorText = ""
        report = "يتم الآن قراءة الملفات وبناء أرشيف محلي..."
        Task.detached(priority: .userInitiated) {
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let outputDirectory = documents.appendingPathComponent("GTA Converter/Local Engine", isDirectory: true)
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                let safeName = folder.lastPathComponent.replacingOccurrences(of: "/", with: "_")
                let output = outputDirectory.appendingPathComponent("\(safeName)-RPF7.rpf")
                let result = try LocalEngineBridge.buildRPF7(from: folder, to: output)
                await MainActor.run {
                    outputFile = output
                    report = """
                    الصيغة: \(result["format"] as? String ?? "RPF7")
                    الملفات: \(result["files"] as? Int ?? 0)
                    الحجم الأصلي: \(ByteCountFormatter.string(fromByteCount: Int64(result["input_bytes"] as? Int64 ?? 0), countStyle: .file))
                    حجم الناتج: \(ByteCountFormatter.string(fromByteCount: Int64(result["output_bytes"] as? Int64 ?? 0), countStyle: .file))
                    المدخلات المفحوصة: \(result["validated_entries"] as? Int ?? 0)
                    \(result["warning"] as? String ?? "")
                    """
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isBusy = false
                }
            }
            if access { folder.stopAccessingSecurityScopedResource() }
        }
    }

    private func convertResource(_ file: URL) {
        let access = file.startAccessingSecurityScopedResource()
        isBusy = true
        errorText = ""
        convertedResourceURL = nil
        report = "يتم تحويل مورد اللعبة محلياً..."
        Task.detached(priority: .userInitiated) {
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let outputDirectory = documents.appendingPathComponent("GTA Converter/Local Engine/Converted", isDirectory: true)
                let result = try LocalEngineBridge.convertResource(at: file, to: outputDirectory)
                let outputPath = result["output"] as? String ?? ""
                await MainActor.run {
                    convertedResourceURL = URL(fileURLWithPath: outputPath)
                    report = """
                    من الامتداد: \(result["input_extension"] as? String ?? "")
                    إلى الامتداد: \(result["output_extension"] as? String ?? "")
                    طريقة المعالجة: \(result["mode"] as? String ?? "")
                    علامات المنصة المعدّلة: \(result["patched_markers"] as? Int ?? 0)
                    حجم الناتج: \(ByteCountFormatter.string(fromByteCount: Int64(result["output_bytes"] as? Int64 ?? 0), countStyle: .file))
                    \(result["warning"] as? String ?? "")
                    """
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isBusy = false
                }
            }
            if access { file.stopAccessingSecurityScopedResource() }
        }
    }

    private func extractYTD(_ file: URL) {
        let access = file.startAccessingSecurityScopedResource()
        isBusy = true
        errorText = ""
        extractedTextureFolder = nil
        report = "يتم تحليل YTD واستخراج الخامات..."
        Task.detached(priority: .userInitiated) {
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let base = documents.appendingPathComponent("GTA Converter/Local Engine/Textures", isDirectory: true)
                let folderName = file.deletingPathExtension().lastPathComponent
                let outputDirectory = base.appendingPathComponent(folderName, isDirectory: true)
                let result = try LocalEngineBridge.extractYTD(at: file, to: outputDirectory)
                await MainActor.run {
                    extractedTextureFolder = outputDirectory
                    report = """
                    الخامات المكتشفة: \(result["textures_found"] as? Int ?? 0)
                    الخامات المستخرجة: \(result["textures_exported"] as? Int ?? 0)
                    حجم DDS الكلي: \(ByteCountFormatter.string(fromByteCount: Int64(result["output_bytes"] as? Int64 ?? 0), countStyle: .file))
                    \(result["warning"] as? String ?? "")
                    """
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isBusy = false
                }
            }
            if access { file.stopAccessingSecurityScopedResource() }
        }
    }

    private func inspect(_ file: URL) {
        let access = file.startAccessingSecurityScopedResource()
        isBusy = true
        errorText = ""
        report = "يتم فحص بنية RPF..."
        Task.detached(priority: .userInitiated) {
            do {
                let result = try LocalEngineBridge.inspectRPF(at: file)
                await MainActor.run {
                    report = """
                    الصيغة: \(result["format"] as? String ?? "غير معروفة")
                    التشفير: \(result["encryption"] as? String ?? "غير معروف")
                    عدد المدخلات: \(result["entries"] as? Int ?? 0)
                    المجلدات: \(result["directories"] as? Int ?? 0)
                    الملفات الثنائية: \(result["binary_files"] as? Int ?? 0)
                    موارد RSC7: \(result["resource_files"] as? Int ?? 0)
                    \(result["warning"] as? String ?? "")
                    """
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                    isBusy = false
                }
            }
            if access { file.stopAccessingSecurityScopedResource() }
        }
    }
}


private extension View {
    func localEnginePanel() -> some View {
        self.background(.ultraThinMaterial)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.08)))
    }
}
