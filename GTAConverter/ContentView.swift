import SwiftUI
import UniformTypeIdentifiers
import SwiftArchive
import UIKit

struct ContentView: View {
    @State private var showingImporter = false
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
    @State private var isDropTargeted = false
    @State private var lastErrorDetails = ""
    @State private var modAnalysis: ModAnalysisReport?
    @AppStorage("gta_conversion_mode") private var conversionMode = "auto"
    @AppStorage("gta_cover_style") private var coverStyle = "neon"
    @AppStorage("gta_accent_color") private var accentColor = "purple"

    private var purple: Color {
        switch accentColor {
        case "blue": return Color(red: 0.20, green: 0.52, blue: 1.0)
        case "green": return Color(red: 0.18, green: 0.72, blue: 0.48)
        case "orange": return Color(red: 1.0, green: 0.48, blue: 0.16)
        case "red": return Color(red: 0.94, green: 0.22, blue: 0.32)
        default: return Color(red: 0.57, green: 0.30, blue: 0.98)
        }
    }
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
                GTAAppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        topMenu
                        conversionCard
                        importCard
                        directLinkCard
                        packCard
                        actionButtons
                        if let outputFolder { outputCard(outputFolder) }
                        if let modAnalysis { modAnalysisCard(modAnalysis) }
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
            .navigationTitle("GTA Converter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AppFilesView()) { Image(systemName: "folder.fill").foregroundStyle(purple) }
                    NavigationLink(destination: AppSettingsView()) { Image(systemName: "gearshape.fill").foregroundStyle(purple) }
                    NavigationLink(destination: AppDiagnosticsView(sourceURL: sourceURL, outputFolder: outputFolder, latestError: lastErrorDetails)) {
                        Image(systemName: "waveform.path.ecg").foregroundStyle(purple)
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                DocumentPickerBridge(contentTypes: importKind == .folder ? [.folder] : [.item]) { result in
                    handleImport(result)
                }
                .ignoresSafeArea()
            }
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("GTA CONVERTER").font(.system(size: 25, weight: .black, design: .rounded)).tracking(-0.5).foregroundStyle(.white)
                    Text("مركز تجهيز مودات قراند").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 19).fill(LinearGradient(colors: [purple, Color(red: 0.34, green: 0.16, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 58, height: 58)
                    Image(systemName: "car.side.fill").font(.system(size: 27, weight: .bold)).foregroundStyle(.white)
                }
            }
            HStack(spacing: 8) { featureTag("ZIP"); featureTag("RAR"); featureTag("مجلدات"); Spacer();
                Text("iOS APP").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(1.1).foregroundStyle(purple.opacity(0.95))
            }
        }.padding(20)
         .background(coverStyle == "minimal"
            ? LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : coverStyle == "dark"
                ? LinearGradient(colors: [Color.black.opacity(0.55), purple.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [purple.opacity(0.30), Color.white.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing))
         .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
         .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.09)))
    }
    private func featureTag(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.white.opacity(0.09)).clipShape(Capsule())
            .foregroundStyle(.white.opacity(0.8))
    }

    private var topMenu: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                menuLink("التحويل السحابي", icon: "cloud.gear.fill", destination: CloudConversionView())
                menuLink("متصفح المودات", icon: "globe", destination: GTAModBrowserView())
                menuLink("مكتبة المودات", icon: "square.grid.2x2.fill", destination: GTAModsLibraryView())
                menuLink("التنزيلات", icon: "arrow.down.circle.fill", destination: GTADownloadsView())
                menuLink("سجل العمليات", icon: "clock.arrow.circlepath", destination: GTATransferHistoryView())
                menuLink("مختبر YTD", icon: "photo.stack.fill", destination: YTDTextureLabView())
                menuLink("التخصيص", icon: "paintpalette.fill", destination: GTAAppearanceSettingsView())
                menuLink("الميزات", icon: "square.grid.2x2", destination: FeatureHubView())
                menuLink("ملفاتي", icon: "folder.fill", destination: AppFilesView())
                menuLink("الإعدادات", icon: "gearshape.fill", destination: AppSettingsView())
                menuLink("التشخيص", icon: "waveform.path.ecg", destination: AppDiagnosticsView(sourceURL: sourceURL, outputFolder: outputFolder, latestError: lastErrorDetails))
                menuLink("المبدع", icon: "person.crop.circle.fill", destination: CreatorPageView())
            }
        }
    }

    private func menuLink<Destination: View>(_ title: String, icon: String, destination: Destination) -> some View {
        NavigationLink(destination: destination) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(.white.opacity(0.075))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(purple.opacity(0.25)))
        }.buttonStyle(.plain)
    }

    private var conversionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("نوع التحويل والتجهيز", icon: "arrow.triangle.2.circlepath")
            Text("اختر Auto ليحدد التطبيق المسار من الملفات، أو حدد النوع يدوياً.")
                .font(.caption).foregroundStyle(.white.opacity(0.58))
            Picker("نوع التجهيز", selection: $conversionMode) {
                Text("Auto").tag("auto")
                Text("سيارات").tag("vehicle")
                Text("خرائط").tag("map")
                Text("شخصيات").tag("character")
                Text("ملفات عامة").tag("files")
            }
            .pickerStyle(.menu).tint(.white)
            .padding(11).frame(maxWidth: .infinity, alignment: .leading)
            .background(purple.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 13))
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(purple)
                Text(conversionModeDescription).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(16).panel()
    }

    private var conversionModeDescription: String {
        switch conversionMode {
        case "vehicle": return "مسار تجهيز مودات السيارات وملفات DLC."
        case "map": return "مسار تجهيز الخرائط وملفات YMAP."
        case "character": return "مسار تجهيز الشخصيات وملفات PED."
        case "files": return "فك وفحص الملفات بدون تصنيف خاص."
        default: return "يحلل أسماء الملفات والمسارات ويختار التصنيف الأقرب تلقائياً."
        }
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("استيراد الملفات", icon: "tray.and.arrow.down.fill")
                Spacer()
                Text("01").font(.system(size: 11, weight: .black, design: .rounded)).foregroundStyle(purple)
            }
            VStack(spacing: 10) {
                Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                    .font(.system(size: 34, weight: .medium)).foregroundStyle(isDropTargeted ? .white : purple)
                Text(isDropTargeted ? "أفلت الملف هنا" : "اسحب الملف وأفلته هنا")
                    .font(.headline.weight(.bold)).foregroundStyle(.white)
                Text("يدعم ZIP وRAR والمجلدات من تطبيق الملفات")
                    .font(.caption).foregroundStyle(.white.opacity(0.58)).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    importButton("اختيار ZIP / RAR", icon: "doc.zipper", kind: .archive)
                    importButton("اختيار مجلد", icon: "folder.fill", kind: .folder)
                }.padding(.top, 4)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
            .background(isDropTargeted ? purple.opacity(0.28) : .black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                    .foregroundStyle(isDropTargeted ? purple : .white.opacity(0.22))
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop)
            HStack(spacing: 11) {
                Image(systemName: sourceURL == nil ? "doc" : "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(sourceURL == nil ? .white.opacity(0.35) : .green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedFileName).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(sourceURL == nil ? "بانتظار اختيار ملف" : "تم حفظ نسخة داخل التطبيق")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
                if sourceURL != nil {
                    Button { sourceURL = nil; selectedFileName = "ما تم اختيار ملف"; outputFolder = nil; modAnalysis = nil } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.white.opacity(0.55))
                    }.buttonStyle(.plain)
                }
            }.padding(13).background(.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 15))
        }.padding(17).panel()
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

    private func modAnalysisCard(_ report: ModAnalysisReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("تحليل بنية المود", icon: "car.side.and.exclamationmark")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                analysisMetric("الملفات", value: "\(report.fileCount)", icon: "doc")
                analysisMetric("ملفات DLC", value: "\(report.dlcFiles.count)", icon: "shippingbox")
                analysisMetric("ملفات YFT", value: "\(report.yftFiles.count)", icon: "car.side")
                analysisMetric("ملفات YTD", value: "\(report.ytdFiles.count)", icon: "photo")
                analysisMetric("ملفات META", value: "\(report.vehicleMetaFiles.count)", icon: "doc.text")
                analysisMetric("FiveM Manifest", value: "\(report.manifestFiles.count)", icon: "curlybraces")
                analysisMetric("أسماء الحزم", value: "\(report.packNames.count)", icon: "tag")
                analysisMetric("ملفات Readme", value: "\(report.readmeFiles.count)", icon: "text.book.closed")
            }
            Text(
                report.isFiveMVehicleResource
                    ? "تم التعرف على مورد سيارة FiveM. ملفات الموديل والخامات وبيانات المركبة موجودة، لكن يلزم تحويلها إلى DLC متوافق مع PS4."
                    : (report.dlcFiles.isEmpty
                        ? "ما لقينا dlc.rpf أو بنية سيارة FiveM مكتملة."
                        : "تم العثور على ملفات DLC. تقدر تستخدم أسماءها لإنشاء dlclist.xml.")
            )
            .font(.caption).foregroundStyle(.white.opacity(0.72))
            if !report.packNames.isEmpty {
                Button {
                    packNames = report.packNames.joined(separator: "\n")
                    status = "تم نقل \(report.packNames.count) اسم DLC إلى مولّد XML."
                    isError = false
                } label: {
                    Label("استخدام أسماء DLC في مولّد XML", systemImage: "arrow.down.doc.fill")
                        .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).padding(12)
                        .background(purple.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            if let outputFolder, !report.dlcFiles.isEmpty {
                NavigationLink(destination: DLCPS4PreparationView(
                    root: outputFolder,
                    dlcFiles: report.dlcFiles,
                    packNames: report.packNames
                )) {
                    Label("تجهيز حزم DLC للـPS4 (Orbx)", systemImage: "shippingbox.and.arrow.down.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity).padding(13)
                        .background(Color.purple.opacity(0.28))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            if !report.duplicatePackNames.isEmpty {
                Text("تنبيه: أسماء متكررة: " + report.duplicatePackNames.joined(separator: "، "))
                    .font(.caption2).foregroundStyle(.orange)
            }
            Button {
                UIPasteboard.general.string = report.reportText
            } label: {
                Label("نسخ تقرير تحليل المود", systemImage: "doc.on.doc")
                    .font(.caption.bold()).frame(maxWidth: .infinity).padding(10)
                    .background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
        .padding(16).panel()
    }

    private func analysisMetric(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(purple).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline.bold()).foregroundStyle(.white)
                Text(title).font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(11).background(.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 12))
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
            VStack(alignment: .leading, spacing: 8) {
                Text(status).font(.caption).foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isError {
                    Button {
                        UIPasteboard.general.string = lastErrorDetails
                    } label: {
                        Label("نسخ الخطأ وسببه", systemImage: "doc.on.doc")
                            .font(.caption.bold()).foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(13).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var footer: some View {
        Text("© 2026 Moa_sa7 • GTA Converter")
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            .multilineTextAlignment(.center).padding(.horizontal, 8)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).foregroundStyle(.white)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let pickedURL = urls.first else { return }
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
                    fail("تعذر استيراد الملف: \(error.localizedDescription)", underlyingError: error)
                }
                isBusy = false
            }
        case .failure(let error):
            fail("تعذر اختيار الملف: \(error.localizedDescription)")
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let supportedTypes = [UTType.fileURL.identifier, UTType.item.identifier, UTType.content.identifier]
        guard let provider = providers.first(where: { item in
            supportedTypes.contains(where: { item.hasItemConformingToTypeIdentifier($0) })
        }), let dropType = supportedTypes.first(where: { providerType in
            provider.hasItemConformingToTypeIdentifier(providerType)
        }) else {
            fail("المصدر هذا ما يرسل رابط ملف قابل للاستيراد.")
            return false
        }
        isBusy = true
        progressText = "جاري استيراد الملف المسحوب..."
        provider.loadFileRepresentation(forTypeIdentifier: dropType) { url, error in
            guard let url = url, error == nil else {
                DispatchQueue.main.async { fail("ما قدرت أقرأ الملف المسحوب. جرّب اختيار الملف من الزر."); isBusy = false }
                return
            }
            do {
                let importedURL = try Self.copyPickedItemIntoAppStorage(url)
                DispatchQueue.main.async {
                    sourceURL = importedURL
                    selectedFileName = url.lastPathComponent
                    status = "تم استيراد الملف المسحوب وحفظه داخل التطبيق."
                    isError = false
                    isBusy = false
                }
            } catch {
                DispatchQueue.main.async { fail("تعذر استيراد الملف المسحوب: " + error.localizedDescription); isBusy = false }
            }
        }
        return true
    }
    nonisolated private static func appManagedFolder(_ name: String) throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = documents.appendingPathComponent("GTA Converter", isDirectory: true)
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    nonisolated private static func copyPickedItemIntoAppStorage(_ source: URL) throws -> URL {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { source.stopAccessingSecurityScopedResource() }
        }

        let fm = FileManager.default
        let documents = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let appRoot = documents.appendingPathComponent("GTA Converter", isDirectory: true)
        let imports = appRoot.appendingPathComponent("Imports", isDirectory: true)
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
                request.setValue("GTAConverter-iOS", forHTTPHeaderField: "User-Agent")
                let (temporary, response) = try await URLSession.shared.download(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw ImportError.http(http.statusCode)
                }
                let ext = url.pathExtension.isEmpty ? "zip" : url.pathExtension
                guard ["zip", "rar"].contains(ext.lowercased()) else {
                    throw ImportError.unsupported
                }
                let destination = try Self.appManagedFolder("Imports")
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
            var currentArchivePath = "لم يبدأ استخراج أي عنصر"
            var incompleteRoot: URL?
            do {
                let root = try Self.appManagedFolder("Ready")
                    .appendingPathComponent("GTA-Prepared-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                incompleteRoot = root

                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    try Self.copyFolderSafely(from: sourceURL, to: root)
                } else {
                    let reader = try await ArchiveReader(reading: .fileURL(sourceURL))
                    var totalBytes: Int64 = 0
                    var count = 0
                    do {
                        while let entry = try await reader.nextEntry() {
                            let raw = entry.path
                            currentArchivePath = raw
                            let relative = try Self.safeRelativePath(raw)
                            let destination = root.appendingPathComponent(relative, isDirectory: entry.fileType == .directory)

                            // Stream each file in bounded chunks instead of buffering a whole YFT/YTD in RAM.
                            switch entry.fileType {
                            case .directory:
                                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

                            case .regular:
                                if entry.hardlinkTarget != nil { continue }
                                try FileManager.default.createDirectory(
                                    at: destination.deletingLastPathComponent(),
                                    withIntermediateDirectories: true
                                )
                                var existingIsDirectory: ObjCBool = false
                                if FileManager.default.fileExists(atPath: destination.path, isDirectory: &existingIsDirectory),
                                   existingIsDirectory.boolValue {
                                    throw ImportError.archivePathConflict(relative)
                                }
                                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                                    throw ImportError.fileWrite(relative)
                                }
                                let output = try FileHandle(forWritingTo: destination)
                                do {
                                    while true {
                                        let chunk = try await reader.readData(maxLength: 1024 * 1024)
                                        if chunk.isEmpty { break }
                                        totalBytes += Int64(chunk.count)
                                        guard totalBytes <= 1_500_000_000, count < 20_000 else {
                                            throw ImportError.archiveTooLarge
                                        }
                                        try output.write(contentsOf: Data(chunk))
                                    }
                                    try output.close()
                                } catch {
                                    try? output.close()
                                    throw error
                                }
                                count += 1

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
                    guard count > 0 else { throw ImportError.emptyArchive }
                }
                let analysis = try await Task.detached(priority: .utility) {
                    try ModAnalyzer.analyze(at: root)
                }.value
                outputFolder = root
                incompleteRoot = nil
                modAnalysis = analysis
                GTATransferHistoryStore.record(title: "فك وتحليل مود", detail: "\(analysis.fileCount) ملف • \(resolvedMode(for: analysis))")
                if analysis.isFiveMVehicleResource {
                    status = "تم التعرف على مورد سيارة FiveM. ملفات YFT: \(analysis.yftFiles.count)، ملفات YTD: \(analysis.ytdFiles.count)، ملفات META: \(analysis.vehicleMetaFiles.count). تم الفحص فقط؛ تحويل PS4 يحتاج بناء DLC."
                } else {
                    status = "اكتمل فك الملفات. المسار المختار: \(resolvedMode(for: analysis)). تم العثور على \(analysis.dlcFiles.count) ملف dlc.rpf. هذا تجهيز وفحص، وليس تحويل PC إلى PS4 تلقائياً."
                }
                isError = false
            } catch {
                fail("تعذر تجهيز الأرشيف عند العنصر «\(currentArchivePath)»: \(error.localizedDescription)", underlyingError: error)
            }
        }
    }

    nonisolated private static func safeRelativePath(_ raw: String) throws -> String {
        let normalized = raw.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true)
        guard !parts.isEmpty, !normalized.hasPrefix("/"),
              !parts.contains(".."), !parts.contains(".") else {
            throw ImportError.unsafePath
        }
        return parts.map(String.init).joined(separator: "/")
    }

    nonisolated private static func copyFolderSafely(from source: URL, to destination: URL) throws {
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

    private func resolvedMode(for report: ModAnalysisReport) -> String {
        if conversionMode != "auto" {
            switch conversionMode {
            case "vehicle": return "سيارات"
            case "map": return "خرائط"
            case "character": return "شخصيات"
            default: return "ملفات عامة"
            }
        }
        if report.isFiveMVehicleResource { return "سيارات FiveM (Auto)" }
        if !report.dlcFiles.isEmpty { return "سيارات (Auto)" }
        if report.yftFiles.isEmpty == false || report.ytdFiles.isEmpty == false {
            return "ملفات مركبة تحتاج مراجعة (Auto)"
        }
        return "ملفات عامة (Auto)"
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
            let url = try Self.appManagedFolder("Ready").appendingPathComponent("dlclist.xml")
            try xml.write(to: url, atomically: true, encoding: .utf8)
            generatedURL = url
            status = "تم إنشاء dlclist.xml بعدد \(names.count) حزمة."
            isError = false
        } catch { fail("فشل إنشاء XML: \(error.localizedDescription)") }
    }

    private func fail(_ message: String, underlyingError: Error? = nil) {
        status = message
        let archiveError = underlyingError as? ArchiveError
        let nsError = underlyingError.map { $0 as NSError } ?? NSError(domain: "GTAConverter", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        let reason = archiveError?.message.isEmpty == false
            ? archiveError!.message
            : (nsError.localizedFailureReason ?? "لم يوفّر النظام سبباً إضافياً.")
        let technicalStage = archiveError.map {
            "مرحلة libarchive: \(String(describing: $0.stage))، الحالة: \(String(describing: $0.status))، الرمز الخام: \($0.code)"
        }
        let suggestion = technicalStage ?? (nsError.localizedRecoverySuggestion ?? "انسخ التقرير وأرسله كما هو لتحديد موضع المشكلة.")
        let reportedCode = archiveError.map { Int($0.code) } ?? nsError.code
        let reportedDomain = archiveError == nil ? nsError.domain : "SwiftArchive.ArchiveError"
        let technicalDescription = archiveError?.description ?? nsError.localizedDescription
        lastErrorDetails = """
        GTA Converter - Error Report
        الوقت: \(ISO8601DateFormatter().string(from: Date()))
        الخطأ: \(message)
        السبب: \(reason)
        الوصف التقني: \(technicalDescription)
        نطاق الخطأ: \(reportedDomain)
        رمز الخطأ: \(reportedCode)
        اقتراح النظام: \(suggestion)
        الملف: \(sourceURL?.lastPathComponent ?? selectedFileName)
        المسار: \(sourceURL?.path ?? "غير متوفر")
        """
        isError = true
    }

    private enum ImportError: LocalizedError {
        case http(Int), unsupported, archiveTooLarge, emptyArchive, unsafePath, folderRead, archivePathConflict(String), fileWrite(String)
        var errorDescription: String? {
            switch self {
            case .http(let code): return "استجابة الموقع: HTTP \(code)"
            case .unsupported: return "الرابط يجب أن ينتهي بملف ZIP أو RAR."
            case .archiveTooLarge: return "الأرشيف أكبر من الحدود الآمنة أو يحتوي ملفات كثيرة."
            case .emptyArchive: return "الأرشيف فارغ أو تنسيقه غير مدعوم."
            case .unsafePath: return "الأرشيف يحتوي مسار ملفات غير آمن وتم إيقاف الفك."
            case .folderRead: return "تعذرت قراءة محتويات المجلد."
            case .archivePathConflict(let path): return "تعارض مسار داخل الأرشيف: \(path). يوجد مجلد في مكان ملف أو العكس."
            case .fileWrite(let name): return "تعذر إنشاء الملف المستخرج: \(name)"
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


private struct DocumentPickerBridge: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let completion: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<[URL], Error>) -> Void
        init(completion: @escaping (Result<[URL], Error>) -> Void) { self.completion = completion }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(.success([]))
        }
    }
}

private struct AppFilesView: View {
    var directory: URL? = nil
    @AppStorage("gta_show_hidden_files") private var showHiddenFiles = false
    @State private var items: [URL] = []
    @State private var search = ""
    @State private var errorText: String?

    private var root: URL {
        directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTA Converter", isDirectory: true)
    }

    var body: some View {
        ZStack {
            GTAAppBackground()
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").font(.system(size: 30)).foregroundStyle(Color.purple)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(directory?.lastPathComponent ?? "ملفات GTA Converter").font(.headline.bold()).foregroundStyle(.white)
                        Text("\(items.count) عنصر").font(.caption).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button(action: loadItems) {
                        Image(systemName: "arrow.clockwise").foregroundStyle(.white).padding(10)
                            .background(.white.opacity(0.08)).clipShape(Circle())
                    }
                }.padding(.horizontal, 16).padding(.top, 10)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.45))
                    TextField("بحث في الملفات", text: $search).foregroundStyle(.white)
                }.padding(12).background(.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 13)).padding(.horizontal, 16)

                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.caption).padding(.horizontal)
                }

                List {
                    ForEach(filteredItems, id: \.standardizedFileURL) { url in
                        fileRow(url)
                            .listRowBackground(Color.white.opacity(0.045))
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
        }
        .navigationTitle("مستكشف الملفات")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadItems)
    }

    private var filteredItems: [URL] {
        items.filter { (showHiddenFiles || !$0.lastPathComponent.hasPrefix(".")) &&
            (search.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(search)) }
    }

    @ViewBuilder private func fileRow(_ url: URL) -> some View {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        HStack(spacing: 11) {
            Image(systemName: isDirectory ? "folder.fill" : icon(for: url))
                .font(.title3).foregroundStyle(isDirectory ? Color.purple : .white.opacity(0.75))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Text(isDirectory ? "مجلد" : fileSize(url)).font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            if isDirectory {
                NavigationLink(destination: AppFilesView(directory: url)) {
                    Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(.white.opacity(0.5))
                }
            } else {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(.white.opacity(0.75)).padding(7)
                }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            ShareLink(item: url) { Label("مشاركة", systemImage: "square.and.arrow.up") }
            Button(role: .destructive) { remove(url) } label: { Label("حذف", systemImage: "trash") }
        }
    }

    private func loadItems() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            items = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            errorText = nil
        } catch { errorText = error.localizedDescription }
    }

    private func remove(_ url: URL) {
        do { try FileManager.default.removeItem(at: url); loadItems() }
        catch { errorText = "تعذر الحذف: " + error.localizedDescription }
    }

    private func fileSize(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func icon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "zip", "rar": return "doc.zipper"
        case "xml", "json", "txt": return "doc.text"
        case "png", "jpg", "jpeg": return "photo"
        default: return "doc"
        }
    }
}

private struct AppSettingsView: View {
    @AppStorage("gta_show_hidden_files") private var showHiddenFiles = false
    @State private var cacheMessage = ""

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.2.fill").font(.system(size: 30)).foregroundStyle(Color.purple)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("إعدادات التطبيق").font(.title3.bold()).foregroundStyle(.white)
                            Text("التخزين وطريقة عرض الملفات").font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                    }.padding(18).background(LinearGradient(colors: [Color.purple.opacity(0.3), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    group("عام", icon: "slider.horizontal.3") {
                        Toggle(isOn: $showHiddenFiles) {
                            Label("إظهار الملفات المخفية", systemImage: "eye").foregroundStyle(.white)
                        }.tint(.purple)
                    }

                    group("التخزين", icon: "internaldrive") {
                        Label("مجلد التطبيق", systemImage: "folder.fill").foregroundStyle(.white)
                        Text("Files > On My iPhone/iPad > GTA Converter")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                        Button {
                            do {
                                let temp = FileManager.default.temporaryDirectory
                                let contents = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
                                for item in contents where item.lastPathComponent.hasPrefix("GTA-") {
                                    try? FileManager.default.removeItem(at: item)
                                }
                                cacheMessage = "تم تنظيف الملفات المؤقتة."
                            } catch { cacheMessage = error.localizedDescription }
                        } label: {
                            Label("تنظيف الملفات المؤقتة", systemImage: "trash")
                                .frame(maxWidth: .infinity).padding(12)
                                .background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }
                        if !cacheMessage.isEmpty { Text(cacheMessage).font(.caption).foregroundStyle(.white.opacity(0.65)) }
                    }

                    group("حول التطبيق", icon: "info.circle") {
                        settingRow("اسم التطبيق", "GTA Converter")
                        settingRow("الإصدار", "1.4.0")
                        settingRow("النظام الأدنى", "iOS 16 أو أحدث")
                    }

                    group("الخصوصية", icon: "lock.shield") {
                        Text("ملفاتك تحفظ محلياً داخل التطبيق ولا يتم رفعها إلى خادم خارجي.")
                            .font(.caption).foregroundStyle(.white.opacity(0.62))
                    }
                }.padding(16)
            }
        }
        .navigationTitle("الإعدادات")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.white)
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func settingRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(.white.opacity(0.7)); Spacer(); Text(value).foregroundStyle(.white) }
            .font(.subheadline)
    }
}
