import SwiftUI
import UniformTypeIdentifiers

struct LocalEngineView: View {
    let initialFolder: URL?
    let initialFile: URL?

    @State private var didAutoProcessInitialFile = false
    @State private var sourceFolder: URL?
    @State private var outputFile: URL?
    @State private var report = ""
    @State private var errorText = ""
    @State private var isBusy = false
    @State private var activePicker: EnginePicker?
    @State private var showingFileImporter = false
    @AppStorage("gta_language") private var appLanguage = "ar"
    private enum EnginePicker {
        case sourceFolder, buildYTD, inspectRPF, extractRPF, convertResource, convertFolder, extractYTD
        var contentTypes: [UTType] {
            switch self {
            case .sourceFolder, .buildYTD, .convertFolder: return [.folder]
            default: return [.item]
            }
        }
    }
    @State private var extractedTextureFolder: URL?
    @State private var convertedResourceURL: URL?
    @State private var builtYtdURL: URL?
    @State private var extractedRpfFolder: URL?
    @State private var convertedFolderURL: URL?

    init(initialFolder: URL? = nil, initialFile: URL? = nil) {
        self.initialFolder = initialFolder
        self.initialFile = initialFile
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
                        Text("محرر ومحرك الملفات المحلي").font(.title2.bold()).foregroundStyle(.white)
                        Text(LocalEngineBridge.version)
                            .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.55))
                        Text("افتح أرشيف RPF7 واستخرج محتوياته، عدّل الملفات في مجلد العمل، ثم أعد بناء الأرشيف محلياً. يدعم أيضاً فحص الموارد واستخراج وبناء YTD بصيغته المدعومة.")
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
                        Button { openPicker(.sourceFolder) } label: {
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

                    Button { openPicker(.inspectRPF) } label: {
                        Label("فحص ملف RPF موجود", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).disabled(isBusy)

                    Button { openPicker(.extractRPF) } label: {
                        Label("استخراج ملفات RPF محلياً", systemImage: "archivebox")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).disabled(isBusy)

                    Button { openPicker(.convertResource) } label: {
                        Label("تحويل مورد Y* إلى O* محلياً", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).disabled(isBusy)

                    Button { openPicker(.convertFolder) } label: {
                        Label("تحويل مجلد موارد كامل دفعة واحدة", systemImage: "folder.badge.gearshape")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).disabled(isBusy)

                    Button { openPicker(.extractYTD) } label: {
                        Label("استخراج خامات YTD إلى DDS", systemImage: "photo.stack")
                            .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                            .background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).disabled(isBusy)

                    Button { openPicker(.buildYTD) } label: {
                        Label("بناء قاموس YTD من DDS والصور", systemImage: "square.stack.3d.up.fill")
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

                    if let convertedFolderURL {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("اكتمل تحويل مجلد الموارد", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(convertedFolderURL.lastPathComponent)
                                .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7))
                            ShareLink(item: convertedFolderURL) {
                                Label("مشاركة مجلد الموارد المحوّل", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(13)
                                    .background(.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                            }
                        }
                        .padding(15).localEnginePanel()
                    }

                    if let extractedRpfFolder {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("تم استخراج ملفات RPF", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(extractedRpfFolder.lastPathComponent)
                                .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7))
                            ShareLink(item: extractedRpfFolder) {
                                Label("مشاركة مجلد الملفات المستخرجة", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(13)
                                    .background(.white.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                            }
                        }
                        .padding(15).localEnginePanel()
                    }

                    if let builtYtdURL {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("تم بناء قاموس YTD وفحصه", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(builtYtdURL.lastPathComponent)
                                .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7))
                            ShareLink(item: builtYtdURL) {
                                Label("مشاركة قاموس YTD", systemImage: "square.and.arrow.up")
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
                        Text("استخراج RPF متاح للأرشيفات غير المشفرة، مع فحص وبناء RPF7 عام. تحويل مورد منفرد أو مجلد كامل واستخراج YTD إلى DDS متاحان. بناء OTD بصيغة Orbis وتجميع DLC متوافق مع PS4 ما زالا قيد النقل والاختبار. حد المعالجة 512MB.")
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
        .onAppear {
            guard let file = initialFile, !didAutoProcessInitialFile else { return }
            didAutoProcessInitialFile = true
            let ext = file.pathExtension.lowercased()
            if ext == "rpf" {
                inspect(file)
            } else if ["yft", "ydr", "ydd", "ypt", "ybn", "ybd", "yld", "yed", "yfd", "ynd", "ynv", "yvr", "ywr", "ypdb", "ycd", "ymap", "ytyp", "ymt", "ymf"].contains(ext) {
                convertResource(file)
            } else if ext == "ytd" {
                extractYTD(file)
            } else {
                report = "تم فتح الملف: \(file.lastPathComponent)\nهذا النوع يحتاج اختيار أداة مناسبة من المحرك أو فك الأرشيف أولاً."
            }
        }
        .environment(\.layoutDirection, appLanguage == "ar" ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: appLanguage))
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: activePicker?.contentTypes ?? [.item],
            allowsMultipleSelection: false
        ) { result in
            let selectedAction = activePicker
            activePicker = nil
            switch result {
            case .failure(let error):
                errorText = error.localizedDescription
            case .success(let urls):
                guard let selectedURL = urls.first, let selectedAction else { return }
                isBusy = true
                errorText = ""
                report = "يتم نسخ الملف المختار إلى مساحة التطبيق..."
                let scopeStarted = selectedURL.startAccessingSecurityScopedResource()
                Task {
                    defer { if scopeStarted { selectedURL.stopAccessingSecurityScopedResource() } }
                    do {
                        let localURL = try await Task.detached(priority: .userInitiated) {
                            try FileImportService.importItem(from: selectedURL, category: "Imports",
                                                              securityScopeAlreadyStarted: scopeStarted)
                        }.value
                        switch selectedAction {
                        case .sourceFolder:
                            var isDirectory: ObjCBool = false
                            guard FileManager.default.fileExists(atPath: localURL.path, isDirectory: &isDirectory),
                                  isDirectory.boolValue else {
                                throw FileImportService.ImportFailure.unsupportedItem
                            }
                            sourceFolder = localURL
                            report = "تم استيراد المجلد وحفظ نسخة محلية داخل التطبيق."
                            isBusy = false
                        case .buildYTD:
                            buildYTD(from: localURL)
                        case .inspectRPF:
                            inspect(localURL)
                        case .extractRPF:
                            extractRPF(localURL)
                        case .convertResource:
                            convertResource(localURL)
                        case .convertFolder:
                            convertFolder(localURL)
                        case .extractYTD:
                            extractYTD(localURL)
                        }
                    } catch {
                        errorText = "تعذر استيراد العنصر المختار: \(error.localizedDescription)"
                        isBusy = false
                    }
                }
            }
        }
    }

    private func openPicker(_ picker: EnginePicker) {
        activePicker = picker
        showingFileImporter = true
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

    private func extractRPF(_ file: URL) {
        let access = file.startAccessingSecurityScopedResource()
        isBusy = true
        errorText = ""
        extractedRpfFolder = nil
        report = "يتم استخراج الملفات وفك الأرشيفات الداخلية..."
        Task.detached(priority: .userInitiated) {
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let base = documents.appendingPathComponent("GTA Converter/Local Engine/Extracted RPF", isDirectory: true)
                let folderName = file.deletingPathExtension().lastPathComponent
                let outputDirectory = base.appendingPathComponent(folderName, isDirectory: true)
                let result = try LocalEngineBridge.extractRPF(at: file, to: outputDirectory)
                await MainActor.run {
                    extractedRpfFolder = outputDirectory
                    report = """
                    الصيغة: \(result["format"] as? String ?? "RPF")
                    الملفات المستخرجة: \(result["files"] as? Int ?? 0)
                    الحجم المستخرج: \(ByteCountFormatter.string(fromByteCount: Int64(result["output_bytes"] as? Int64 ?? 0), countStyle: .file))
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

    private func convertFolder(_ folder: URL) {
        let access = folder.startAccessingSecurityScopedResource()
        isBusy = true
        errorText = ""
        convertedFolderURL = nil
        report = "يتم تحويل موارد المجلد ونسخ ملفات البيانات..."
        Task.detached(priority: .userInitiated) {
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let base = documents.appendingPathComponent("GTA Converter/Local Engine/Batch Converted", isDirectory: true)
                let safeName = folder.lastPathComponent.replacingOccurrences(of: "/", with: "_")
                let output = base.appendingPathComponent("\(safeName)-PS4", isDirectory: true)
                let result = try LocalEngineBridge.convertFolder(at: folder, to: output)
                await MainActor.run {
                    convertedFolderURL = output
                    report = """
                    الموارد المحوّلة: \(result["converted_resources"] as? Int ?? 0)
                    الملفات المنسوخة: \(result["copied_files"] as? Int ?? 0)
                    علامات المنصة المعدّلة: \(result["patched_markers"] as? Int ?? 0)
                    الحجم الأصلي: \(ByteCountFormatter.string(fromByteCount: Int64(result["input_bytes"] as? Int64 ?? 0), countStyle: .file))
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

    private func buildYTD(from folder: URL) {
        let access = folder.startAccessingSecurityScopedResource()
        isBusy = true
        errorText = ""
        builtYtdURL = nil
        report = "يتم قراءة DDS والصور وبناء قاموس YTD محلياً..."
        Task.detached(priority: .userInitiated) {
            do {
                let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                            appropriateFor: nil, create: true)
                let outputDirectory = documents.appendingPathComponent("GTA Converter/Local Engine/Texture Dictionaries", isDirectory: true)
                try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                let safeName = folder.lastPathComponent.replacingOccurrences(of: "/", with: "_")
                let output = outputDirectory.appendingPathComponent("\(safeName).ytd")
                let result = try LocalEngineBridge.buildYTD(from: folder, to: output)
                await MainActor.run {
                    builtYtdURL = output
                    report = """
                    الصيغة: \(result["format"] as? String ?? "YTD")
                    الخامات المضمنة: \(result["textures"] as? Int ?? 0)
                    الحجم الأصلي: \(ByteCountFormatter.string(fromByteCount: Int64(result["input_bytes"] as? Int64 ?? 0), countStyle: .file))
                    حجم الناتج: \(ByteCountFormatter.string(fromByteCount: Int64(result["output_bytes"] as? Int64 ?? 0), countStyle: .file))
                    الخامات التي اجتازت الفحص: \(result["validated_textures"] as? Int ?? 0)
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
    @ViewBuilder
    func localEnginePanel() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.08)))
        } else {
            self.background(.ultraThinMaterial)
                .background(Color.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.08)))
        }
    }
}
