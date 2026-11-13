import SwiftUI
import UniformTypeIdentifiers
import SwiftArchive
import UIKit

struct ContentView: View {
    let initialSourceURL: URL?
    @State private var didApplyInitialSource = false
    @State private var showingImporter = false
    @State private var readyModMode = false
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
    @AppStorage("gta_home_density") private var homeDensity = "comfortable"
    @AppStorage("gta_motion_enabled") private var motionEnabled = true
    @AppStorage("gta_language") private var appLanguage = "ar"
    @AppStorage("gta_welcome_message") private var welcomeMessage = "حيّاك في INRPF"
    @AppStorage("gta_background_color") private var backgroundStyle = "midnight"
    @AppStorage("inrpf_theme_id") private var themeID = "purple-night"
    @AppStorage("inrpf_home_menu_order") private var homeMenuOrder = ""
    @AppStorage("inrpf_home_menu_style") private var homeMenuStyle = "pill"
    @AppStorage("inrpf_home_menu_position") private var homeMenuPosition = "top"
    @AppStorage("gta_onboarding_complete") private var onboardingComplete = false
    @State private var showOnboarding = false

    init(initialSourceURL: URL? = nil) {
        self.initialSourceURL = initialSourceURL
        _sourceURL = State(initialValue: initialSourceURL)
        _selectedFileName = State(initialValue: initialSourceURL?.lastPathComponent ?? "ما تم اختيار ملف")
    }

    private var purple: Color {
        switch accentColor {
        case "blue": return Color(red: 0.20, green: 0.52, blue: 1.0)
        case "green": return Color(red: 0.18, green: 0.72, blue: 0.48)
        case "orange": return Color(red: 1.0, green: 0.48, blue: 0.16)
        case "red": return Color(red: 0.94, green: 0.22, blue: 0.32)
        case "cyan": return Color(red: 0.10, green: 0.82, blue: 0.95)
        case "pink": return Color(red: 0.96, green: 0.28, blue: 0.65)
        case "teal": return Color(red: 0.08, green: 0.72, blue: 0.67)
        case "gold": return Color(red: 0.91, green: 0.67, blue: 0.18)
        case "crimson": return Color(red: 0.78, green: 0.10, blue: 0.22)
        case "ice": return Color(red: 0.55, green: 0.78, blue: 1.0)
        case "lime": return Color(red: 0.58, green: 0.82, blue: 0.20)
        case "violet": return Color(red: 0.42, green: 0.20, blue: 0.85)
        default: return Color(red: 0.57, green: 0.30, blue: 0.98)
        }
    }
    private var navigationBackground: Color {
        switch backgroundStyle {
        case "black": return .black
        case "navy": return Color(red: 0.015, green: 0.045, blue: 0.12)
        case "graphite": return Color(red: 0.075, green: 0.08, blue: 0.11)
        default: return Color(red: 0.035, green: 0.025, blue: 0.065)
        }
    }

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
                    VStack(spacing: homeDensity == "compact" ? 8 : 13) {
                        ForEach(themeLayoutOrder, id: \.self) { section in
                            homeSection(section)
                                .gtaScrollGlassMotion(motionEnabled)
                                .modifier(INRPFThemeSurface(themeIndex: activeThemeIndex, tint: purple))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("INRPF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(navigationBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .animation(motionEnabled ? .spring(response: 0.48, dampingFraction: 0.82) : .easeOut(duration: 0.12), value: sourceURL)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavigationLink(destination: INRPFDeviceTestLabView()) {
                        Image(systemName: "ipad.and.iphone").foregroundStyle(purple)
                    }
                    .accessibilityLabel("مختبر الجهاز")
                    NavigationLink(destination: AppFilesView()) { Image(systemName: "folder.fill").foregroundStyle(purple) }
                    NavigationLink(destination: AppSettingsView()) { Image(systemName: "gearshape.fill").foregroundStyle(purple) }
                    NavigationLink(destination: AppDiagnosticsView(sourceURL: sourceURL, outputFolder: outputFolder, latestError: lastErrorDetails)) {
                        Image(systemName: "waveform.path.ecg").foregroundStyle(purple)
                    }
                }
            }
            .sheet(isPresented: $showingImporter) {
                INRPFDocumentPickerPresenter(
                    contentTypes: importKind == .folder ? [.folder] : [.data],
                    onCompletion: handleImport
                )
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
        .environment(\.layoutDirection, appLanguage == "ar" ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: appLanguage))
        .onAppear {
            showOnboarding = !onboardingComplete
            if let initialSourceURL, !didApplyInitialSource {
                didApplyInitialSource = true
                sourceURL = initialSourceURL
                selectedFileName = initialSourceURL.lastPathComponent
                status = "تم تحديد الملف. بدأ فك المود وفحصه تلقائياً..."
                isError = false
                processSource(from: initialSourceURL)
            }
        }
        // Supports Files > Share/Open In > INRPF for registered document types.
        .onOpenURL { url in
            guard url.isFileURL else {
                fail("المصدر الوارد ليس ملفاً محلياً قابلاً للاستيراد.")
                return
            }
            handleImport(.success([url]))
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            GTAOnboardingView { onboardingComplete = true; showOnboarding = false }
        }
    }

    private var themeIDs: [String] {
        ["purple-night","blue-ocean","emerald","sunset","ruby","cyber-cyan","pink-neon","teal-matrix","gold-lux","crimson","ice-storm","lime-dark","royal-violet","blue-carbon","green-midnight","orange-black","pink-graphite","cyan-midnight","gold-navy","red-carbon"]
    }
    private var activeThemeIndex: Int { themeIDs.firstIndex(of: themeID) ?? 0 }
    private var themeLayoutOrder: [String] {
        let sections = ["header","ready","conversion","import","link","packs","actions","output","analysis","orbx","xml","status","menu","footer"]
        let index = activeThemeIndex
        let arranged = index >= 14 ? Array(sections.reversed()) : sections
        let offset = index % sections.count
        return Array(arranged[offset...]) + Array(arranged[..<offset])
    }
    @ViewBuilder private func homeSection(_ key: String) -> some View {
        switch key {
        case "header": header
        case "ready": readyModQuestionCard
        case "conversion": conversionCard
        case "import": importCard
        case "link": directLinkCard
        case "packs": packCard
        case "actions": actionButtons
        case "output": if let outputFolder { outputCard(outputFolder) } else { EmptyView() }
        case "analysis": if let modAnalysis { modAnalysisCard(modAnalysis) } else { EmptyView() }
        case "orbx":
            if let outputFolder, let modAnalysis, !modAnalysis.dlcFiles.isEmpty, !modAnalysis.packNames.isEmpty {
                NavigationLink(destination: DLCPS4PreparationView(root: outputFolder, dlcFiles: modAnalysis.dlcFiles, packNames: modAnalysis.packNames)) {
                    Label("تجهيز وإرسال المود إلى PS4 عبر Orbx", systemImage: "gamecontroller.fill")
                        .font(.headline.bold()).frame(maxWidth: .infinity).padding(15)
                        .background(purple.opacity(0.86)).clipShape(RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                }.buttonStyle(.plain)
            } else { EmptyView() }
        case "xml": if let generatedURL { xmlShareCard(generatedURL) } else { EmptyView() }
        case "status": statusCard
        case "menu": topMenu
        default: footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("GTA CONVERTER").font(.system(size: 25, weight: .black, design: .rounded)).tracking(-0.5).foregroundStyle(.white)
                    Text(welcomeMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (appLanguage == "ar" ? "مركز تجهيز مودات قراند" : "GTA V mod preparation center") : welcomeMessage)
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(2)
                }
                Spacer()
                ZStack {
                    RoundedRectangle(cornerRadius: 19).fill(LinearGradient(colors: [purple, Color(red: 0.34, green: 0.16, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 58, height: 58)
                    Image(systemName: "car.side.fill").font(.system(size: 27, weight: .bold)).foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating, isActive: motionEnabled && ["cyber-cyan","pink-neon","teal-matrix","ice-storm","cyan-midnight"].contains(themeID))
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

    private struct HomeMenuEntry: Identifiable {
        let id: String
        let title: String
        let icon: String
    }

    private var homeMenuEntries: [HomeMenuEntry] {
        [
            .init(id: "engine", title: "المحرك المحلي", icon: "cpu.fill"),
            .init(id: "fivem", title: "استوديو FiveM", icon: "car.side.3.fill"),
            .init(id: "ftp", title: "FTP جهاز PS4", icon: "network"),
            .init(id: "orbx", title: "إرسال تلقائي للسوني", icon: "gamecontroller.fill"),
            .init(id: "rpf", title: "محرر RPF", icon: "archivebox.fill"),
            .init(id: "rpf-python", title: "RPF Studio / فاحص Python", icon: "terminal.fill"),
            .init(id: "cloud", title: "التحويل السحابي (احتياطي)", icon: "cloud.gear.fill"),
            .init(id: "browser", title: "متصفح المودات", icon: "globe"),
            .init(id: "library", title: "مكتبة المودات", icon: "square.grid.2x2.fill"),
            .init(id: "downloads", title: "التنزيلات", icon: "arrow.down.circle.fill"),
            .init(id: "history", title: "سجل العمليات", icon: "clock.arrow.circlepath"),
            .init(id: "ytd", title: "محرر YTD", icon: "photo.stack.fill"),
            .init(id: "setup", title: "التخصيص واللغة", icon: "paintpalette.fill"),
            .init(id: "features", title: "الميزات", icon: "square.grid.2x2"),
            .init(id: "files", title: "ملفاتي", icon: "folder.fill"),
            .init(id: "settings", title: "الإعدادات", icon: "gearshape.fill"),
            .init(id: "diagnostics", title: "استكشاف المشاكل وحلها", icon: "wrench.and.screwdriver.fill"),
            .init(id: "device-test", title: "مختبر الجهاز", icon: "ipad.and.iphone"),
            .init(id: "creator", title: "المبدع", icon: "person.crop.circle.fill"),
            .init(id: "customize", title: "ترتيب القوائم", icon: "rectangle.3.group")
        ]
    }

    private var orderedHomeMenuEntries: [HomeMenuEntry] {
        let saved = homeMenuOrder.split(separator: ",").map(String.init)
        let byID = Dictionary(uniqueKeysWithValues: homeMenuEntries.map { ($0.id, $0) })
        return saved.compactMap { byID[$0] } + homeMenuEntries.filter { !saved.contains($0.id) }
    }

    private var topMenu: some View {
        Group {
            if homeMenuStyle == "list" {
                VStack(spacing: 8) {
                    ForEach(orderedHomeMenuEntries) { entry in homeMenuButton(entry) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(orderedHomeMenuEntries) { entry in homeMenuButton(entry) }
                    }
                }
            }
        }
    }

    private func homeMenuButton(_ entry: HomeMenuEntry) -> some View {
        NavigationLink(destination: homeMenuDestination(entry.id).gtaMotionEntrance()) {
            Label(entry.title, systemImage: entry.icon)
                .font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(maxWidth: homeMenuStyle == "list" ? .infinity : nil,
                       alignment: homeMenuStyle == "list" ? .leading : .center)
                .padding(.horizontal, homeMenuStyle == "list" ? 14 : 13)
                .padding(.vertical, 12)
                .background(homeMenuStyle == "minimal" ? Color.clear : Color.white.opacity(0.075))
                .clipShape(RoundedRectangle(cornerRadius: homeMenuStyle == "card" ? 12 : 22))
                .overlay {
                    if homeMenuStyle != "minimal" {
                        RoundedRectangle(cornerRadius: homeMenuStyle == "card" ? 12 : 22)
                            .stroke(purple.opacity(0.25))
                    }
                }
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private func homeMenuDestination(_ id: String) -> some View {
        switch id {
        case "engine": LocalEngineView(initialFolder: outputFolder)
        case "fivem": FiveMStudioView()
        case "ftp": FTPBrowserView()
        case "orbx": OrbxPS4TransferView()
        case "rpf": LocalEngineView(initialFolder: outputFolder)
        case "rpf-python": RPFStudioView()
        case "cloud": CloudConversionView()
        case "browser": GTAModBrowserView()
        case "library": GTAModsLibraryView()
        case "downloads": GTADownloadsView()
        case "history": GTATransferHistoryView()
        case "ytd": YTDTextureLabView()
        case "setup": GTASetupSettingsView()
        case "features": FeatureHubView()
        case "files": AppFilesView()
        case "settings": AppSettingsView()
        case "diagnostics": AppDiagnosticsView(sourceURL: sourceURL, outputFolder: outputFolder, latestError: lastErrorDetails)
        case "device-test": INRPFDeviceTestLabView()
        case "creator": CreatorPageView()
        default: HomeMenuCustomizationView()
        }
    }

    private var readyModQuestionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("هل لديك ملف جاهز؟", icon: "shippingbox.fill")
            Text("إذا وصلك مود محوّل ومتوافق مع PS4، استورده مباشرة بدون إعادة تحويله.")
                .font(.caption).foregroundStyle(.white.opacity(0.62))
            HStack(spacing: 10) {
                Button {
                    readyModMode = true
                    importKind = .archive
                    showingImporter = true
                } label: {
                    Label("نعم، لدي ملف جاهز", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                        .background(purple.opacity(0.30)).clipShape(RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
                Button {
                    readyModMode = false
                    status = "تم اختيار التحويل المعتاد. استورد مود PC أو FiveM للبدء."
                    isError = false
                } label: {
                    Label("لا، أريد التحويل", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                        .background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            if readyModMode {
                Text("اختر ZIP أو RAR يحتوي حزمة DLC جاهزة. سيتحقق INRPF من وجود dlc.rpf قبل إكمال التجهيز.")
                    .font(.caption2).foregroundStyle(.green.opacity(0.9))
            }
        }.padding(16).panel()
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
            Button(action: { processSource() }) {
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
            if report.isFiveMVehicleResource {
                NavigationLink(destination: LocalEngineView(initialFolder: outputFolder)) {
                    Label("فتح المحرك المحلي وفحص ملفات FiveM", systemImage: "cpu.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity).padding(13)
                        .background(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.22)))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                NavigationLink(destination: CloudConversionView()) {
                    Label("المسار السحابي الاحتياطي", systemImage: "cloud.gear.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity).padding(11)
                        .background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                Text("المحرك المحلي الحالي يفحص ويبني أرشيف RPF7 عاماً. تحويل موارد FiveM إلى موارد PS4 لم يكتمل بعد، لذلك لا تعتبر ملف RPF الناتج حزمة PS4 جاهزة.")
                    .font(.caption2).foregroundStyle(.orange.opacity(0.9))
            }
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
        Text("© 2026 Moa_sa7 • INRPF")
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            .multilineTextAlignment(.center).padding(.horizontal, 8)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).foregroundStyle(.white)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        showingImporter = false
        switch result {
        case .success(let urls):
            guard let pickedURL = urls.first else { return }
            isBusy = true
            progressText = "جاري استيراد الملف إلى التطبيق..."
            let scopeStarted = pickedURL.startAccessingSecurityScopedResource()
            Task {
                defer { if scopeStarted { pickedURL.stopAccessingSecurityScopedResource() } }
                do {
                    let importedURL = try await Task.detached(priority: .userInitiated) {
                        try FileImportService.importItem(from: pickedURL, category: "Imports",
                                                          securityScopeAlreadyStarted: scopeStarted)
                    }.value
                    sourceURL = importedURL
                    selectedFileName = pickedURL.lastPathComponent
                    status = "تم الاستيراد. بدأ فك المود وفحصه تلقائياً..."
                    isError = false
                    isBusy = false
                    processSource(from: importedURL)
                } catch {
                    fail("تعذر استيراد الملف: \(error.localizedDescription)", underlyingError: error)
                    isBusy = false
                }
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
                    status = "تم الاستيراد. بدأ فك المود وفحصه تلقائياً..."
                    isError = false
                    isBusy = false
                    processSource(from: importedURL)
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
        try FileImportService.importItem(from: source, category: "Imports")
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
                status = "اكتمل التحميل. بدأ فك المود وفحصه تلقائياً..."
                isError = false
                processSource(from: destination)
            } catch {
                fail("فشل التحميل: \(error.localizedDescription)")
            }
        }
    }

    private func processSource(from sourceOverride: URL? = nil) {
        guard let sourceURL = sourceOverride ?? self.sourceURL else { return }
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
                if readyModMode && analysis.dlcFiles.isEmpty {
                    throw NSError(domain: "INRPF.ReadyMod", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "الملف المحدد ليس مود DLC جاهزاً: لم يتم العثور على dlc.rpf. اختر حزمة PS4 محوّلة مسبقاً بصيغة ZIP أو RAR."])
                }
                outputFolder = root
                incompleteRoot = nil
                modAnalysis = analysis
                if !analysis.packNames.isEmpty {
                    packNames = analysis.packNames.joined(separator: "\n")
                }
                GTATransferHistoryStore.record(title: "فك وتحليل مود", detail: "\(analysis.fileCount) ملف • \(resolvedMode(for: analysis))")
                if readyModMode {
                    status = "تم التحقق من المود الجاهز والعثور على \(analysis.dlcFiles.count) ملف dlc.rpf. لم تتم إعادة تحويله. استخدم زر تجهيز حزم DLC للـPS4 (Orbx) لإكمال وضعه في مسار التثبيت."
                    readyModMode = false
                } else if analysis.isFiveMVehicleResource {
                    status = "تم التعرف على مورد سيارة FiveM. ملفات YFT: \(analysis.yftFiles.count)، ملفات YTD: \(analysis.ytdFiles.count)، ملفات META: \(analysis.vehicleMetaFiles.count). تم الفحص فقط؛ تحويل PS4 يحتاج بناء DLC."
                } else {
                    status = "اكتمل فك الملفات. المسار المختار: \(resolvedMode(for: analysis)). تم العثور على \(analysis.dlcFiles.count) ملف dlc.rpf. هذا تجهيز وفحص، وليس تحويل PC إلى PS4 تلقائياً."
                }
                isError = false
            } catch {
                if let incompleteRoot {
                    try? FileManager.default.removeItem(at: incompleteRoot)
                }
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
        let entries = names.map { "        <Item>/Data/orbx/gta/rpf/dlc_addon/\($0)/</Item>" }
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
        readyModMode = false
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
    // Keep this modifier type-simple. The previous scrollTransition builder caused
    // recursive SwiftUI generic metadata expansion and a main-thread stack overflow
    // during the first ContentView render on iOS 27.
    func gtaScrollGlassMotion(_ enabled: Bool) -> some View {
        self
    }

    @ViewBuilder
    func panel() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.07)))
        } else {
            self.background(.ultraThinMaterial)
                .background(Color.white.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.055)))
        }
    }
}

extension ArchiveError: @retroactive LocalizedError {
    public var errorDescription: String? {
        description
    }

    public var failureReason: String? {
        message.isEmpty ? "libarchive لم يقدّم وصفاً إضافياً للخطأ." : message
    }

    public var recoverySuggestion: String? {
        "تحقق من سلامة ملف RAR، وكلمة المرور إن كان محمياً، ودعم طريقة الضغط المستخدمة."
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
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: false)
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

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems, id: \.standardizedFileURL) { url in
                            fileRow(url)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)
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
        NavigationLink {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                AppFilesView(directory: url)
            } else {
                AppFileDetailView(url: url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                      ? "folder.fill" : icon(for: url))
                    .font(.title2)
                    .foregroundStyle((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                                     ? Color.purple : .white.opacity(0.8))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
                         ? "مجلد • اضغط لفتحه" : fileSize(url) + " • اضغط لعرض الملف")
                        .font(.caption2).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.left")
                    .font(.caption.bold()).foregroundStyle(.white.opacity(0.45))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

private struct AppIconPickerView: View {
    let language: String
    let tint: Color
    @State private var currentIcon = UIApplication.shared.alternateIconName
    @State private var isChanging = false
    @State private var message = ""

    private struct IconChoice: Identifiable {
        let id: String
        let titleAR: String
        let titleEN: String
        let subtitleAR: String
        let subtitleEN: String
        let symbol: String
        let colors: [Color]
    }

    private let choices: [IconChoice] = [
        .init(id: "primary", titleAR: "INRPF الجديد", titleEN: "INRPF Purple", subtitleAR: "الهوية البنفسجية الأساسية", subtitleEN: "Main purple identity", symbol: "car.side.fill", colors: [Color(red: 0.30, green: 0.08, blue: 0.68), Color(red: 0.05, green: 0.03, blue: 0.13)]),
        .init(id: "AppIcon-Classic", titleAR: "الكلاسيكي القديم", titleEN: "Classic GTA", subtitleAR: "التصميم السابق", subtitleEN: "Previous design", symbol: "road.lanes.curved.left", colors: [Color(red: 0.10, green: 0.10, blue: 0.13), Color(red: 0.55, green: 0.08, blue: 0.12)]),
        .init(id: "AppIcon-Cyber", titleAR: "سايبر أزرق", titleEN: "Cyber Blue", subtitleAR: "أزرق نيون وتقني", subtitleEN: "Neon blue tech style", symbol: "bolt.fill", colors: [Color(red: 0.02, green: 0.42, blue: 0.72), Color(red: 0.02, green: 0.05, blue: 0.16)]),
        .init(id: "AppIcon-Carbon", titleAR: "كربون", titleEN: "Carbon", subtitleAR: "أسود ورمادي هادئ", subtitleEN: "Minimal graphite", symbol: "square.stack.3d.up.fill", colors: [Color(red: 0.26, green: 0.29, blue: 0.34), Color.black]),
        .init(id: "AppIcon-Gold", titleAR: "ذهبي", titleEN: "Gold Edition", subtitleAR: "أسود مع لمسات ذهبية", subtitleEN: "Black with gold accents", symbol: "crown.fill", colors: [Color(red: 0.62, green: 0.39, blue: 0.05), Color(red: 0.07, green: 0.05, blue: 0.02)])
    ]

    private var isArabic: Bool { language == "ar" }
    private func isSelected(_ choice: IconChoice) -> Bool {
        choice.id == "primary" ? currentIcon == nil : currentIcon == choice.id
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(isArabic ? "اختر شكل الأيقونة التي تظهر على الشاشة الرئيسية" : "Choose the icon shown on your Home Screen")
                .font(.caption).foregroundStyle(.white.opacity(0.62))
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(choices) { choice in
                    Button { apply(choice) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(LinearGradient(colors: choice.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.17), lineWidth: 1)
                                Image(systemName: choice.symbol)
                                    .font(.system(size: 29, weight: .bold))
                                    .foregroundStyle(.white)
                                VStack {
                                    HStack {
                                        Spacer()
                                        if isSelected(choice) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3).foregroundStyle(.white)
                                                .background(Circle().fill(.black.opacity(0.35)))
                                        }
                                    }
                                    Spacer()
                                    HStack {
                                        Text("INRPF").font(.system(size: 9, weight: .black, design: .rounded)).tracking(1.4)
                                        Spacer()
                                    }.foregroundStyle(.white.opacity(0.8))
                                }.padding(9)
                            }
                            .frame(height: 92)
                            Text(isArabic ? choice.titleAR : choice.titleEN)
                                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                .lineLimit(1)
                            Text(isArabic ? choice.subtitleAR : choice.subtitleEN)
                                .font(.caption2).foregroundStyle(.white.opacity(0.55))
                                .lineLimit(2)
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected(choice) ? tint.opacity(0.2) : .white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(isSelected(choice) ? tint : .white.opacity(0.08), lineWidth: isSelected(choice) ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(isChanging || isSelected(choice) || !UIApplication.shared.supportsAlternateIcons)
                }
            }
            if isChanging {
                HStack(spacing: 8) { ProgressView().tint(tint); Text(isArabic ? "يتم تغيير الأيقونة..." : "Changing icon...").font(.caption) }
                    .foregroundStyle(.white.opacity(0.7))
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(isArabic ? "iOS قد يعرض تنبيه تأكيد عند تغيير الأيقونة." : "iOS may show a confirmation alert when the icon changes.")
                .font(.caption2).foregroundStyle(.white.opacity(0.48))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func apply(_ choice: IconChoice) {
        guard UIApplication.shared.supportsAlternateIcons else {
            message = isArabic ? "تغيير الأيقونات غير مدعوم في هذا الإصدار." : "Alternate icons are not supported."
            return
        }
        isChanging = true
        message = ""
        let target: String? = choice.id == "primary" ? nil : choice.id
        UIApplication.shared.setAlternateIconName(target) { error in
            DispatchQueue.main.async {
                isChanging = false
                if let error {
                    message = error.localizedDescription
                } else {
                    currentIcon = target
                }
            }
        }
    }
}

private struct INRPFThemePickerView: View {
    let language: String
    @AppStorage("gta_accent_color") private var accent = "purple"
    @AppStorage("gta_background_color") private var background = "midnight"
    @AppStorage("inrpf_theme_id") private var themeID = "purple-night"
    private struct Theme: Identifiable {
        let id, ar, en, accent, background, layout: String
        let colors: [Color]
        let animated: Bool
    }
    private let themes: [Theme] = [
        .init(id:"purple-night",ar:"بنفسجي ليلي",en:"Purple Night",accent:"purple",background:"midnight",layout:"لوحة كلاسيكية",colors:[Color(red:0.57,green:0.30,blue:0.98),Color(red:0.035,green:0.025,blue:0.065)],animated:false),
        .init(id:"blue-ocean",ar:"محيط أزرق",en:"Ocean Blue",accent:"blue",background:"navy",layout:"شبكة مربعات",colors:[.blue,Color(red:0.015,green:0.045,blue:0.12)],animated:false),
        .init(id:"emerald",ar:"زمردي",en:"Emerald",accent:"green",background:"black",layout:"قائمة جانبية",colors:[.green,.black],animated:false),
        .init(id:"sunset",ar:"غروب",en:"Sunset",accent:"orange",background:"graphite",layout:"بطاقة رئيسية",colors:[.orange,Color(red:0.075,green:0.08,blue:0.11)],animated:false),
        .init(id:"ruby",ar:"ياقوتي",en:"Ruby",accent:"red",background:"black",layout:"قائمة مضغوطة",colors:[.red,.black],animated:false),
        .init(id:"cyber-cyan",ar:"سايبر سماوي",en:"Cyber Cyan",accent:"cyan",background:"navy",layout:"سايبر",colors:[.cyan,Color(red:0.015,green:0.045,blue:0.12)],animated:true),
        .init(id:"pink-neon",ar:"نيون وردي",en:"Pink Neon",accent:"pink",background:"black",layout:"شبكة عائمة",colors:[.pink,.black],animated:true),
        .init(id:"teal-matrix",ar:"تيال ماتريكس",en:"Teal Matrix",accent:"teal",background:"graphite",layout:"طرفية تقنية",colors:[.teal,Color(red:0.075,green:0.08,blue:0.11)],animated:true),
        .init(id:"gold-lux",ar:"ذهبي فاخر",en:"Gold Luxe",accent:"gold",background:"black",layout:"تحرير فاخر",colors:[Color(red:0.91,green:0.67,blue:0.18),.black],animated:false),
        .init(id:"crimson",ar:"قرمزي",en:"Crimson",accent:"crimson",background:"midnight",layout:"بطاقات حادة",colors:[Color(red:0.78,green:0.10,blue:0.22),Color(red:0.035,green:0.025,blue:0.065)],animated:false),
        .init(id:"ice-storm",ar:"جليدي",en:"Ice Storm",accent:"ice",background:"navy",layout:"زجاج متحرك",colors:[Color(red:0.55,green:0.78,blue:1.0),Color(red:0.015,green:0.045,blue:0.12)],animated:true),
        .init(id:"lime-dark",ar:"ليموني داكن",en:"Lime Dark",accent:"lime",background:"black",layout:"لوحة أدوات",colors:[Color(red:0.58,green:0.82,blue:0.20),.black],animated:false),
        .init(id:"royal-violet",ar:"بنفسجي ملكي",en:"Royal Violet",accent:"violet",background:"graphite",layout:"تخطيط متدرج",colors:[Color(red:0.42,green:0.20,blue:0.85),Color(red:0.075,green:0.08,blue:0.11)],animated:false),
        .init(id:"blue-carbon",ar:"كربون أزرق",en:"Blue Carbon",accent:"blue",background:"graphite",layout:"كربون هندسي",colors:[.blue,Color(red:0.075,green:0.08,blue:0.11)],animated:false),
        .init(id:"green-midnight",ar:"أخضر منتصف الليل",en:"Midnight Green",accent:"green",background:"midnight",layout:"تنقل سفلي",colors:[.green,Color(red:0.035,green:0.025,blue:0.065)],animated:false),
        .init(id:"orange-black",ar:"برتقالي وأسود",en:"Orange Black",accent:"orange",background:"black",layout:"لوحة تحكم",colors:[.orange,.black],animated:false),
        .init(id:"pink-graphite",ar:"وردي فحمي",en:"Pink Graphite",accent:"pink",background:"graphite",layout:"بطاقات متداخلة",colors:[.pink,Color(red:0.075,green:0.08,blue:0.11)],animated:false),
        .init(id:"cyan-midnight",ar:"سماوي ليلي",en:"Cyan Midnight",accent:"cyan",background:"midnight",layout:"نيون ليلي",colors:[.cyan,Color(red:0.035,green:0.025,blue:0.065)],animated:true),
        .init(id:"gold-navy",ar:"ذهبي وكحلي",en:"Gold Navy",accent:"gold",background:"navy",layout:"تقسيم احترافي",colors:[Color(red:0.91,green:0.67,blue:0.18),Color(red:0.015,green:0.045,blue:0.12)],animated:false),
        .init(id:"red-carbon",ar:"أحمر كربوني",en:"Red Carbon",accent:"crimson",background:"graphite",layout:"قائمة صناعية",colors:[Color(red:0.78,green:0.10,blue:0.22),Color(red:0.075,green:0.08,blue:0.11)],animated:false)
    ]
    private var selected: Theme? { themes.first { $0.id == themeID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language == "ar" ? "20 تصميم مستقل" : "20 distinct designs").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.65))
                Spacer()
                if let selected { Text(language == "ar" ? selected.ar : selected.en).font(.caption.bold()).foregroundStyle(selected.colors[0]) }
            }
            LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], spacing: 10) {
                ForEach(themes.indices, id: \.self) { index in
                    let theme = themes[index]
                    let isSelected = theme.id == themeID
                    Button {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                            themeID = theme.id
                            accent = theme.accent
                            background = theme.background
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: index % 4 == 0 ? 7 : 14)
                                    .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(height: 72)
                                    .overlay(alignment: .bottomLeading) {
                                        HStack(alignment: .bottom, spacing: 4) {
                                            ForEach(0..<5, id: \.self) { n in
                                                RoundedRectangle(cornerRadius: index % 4 == 0 ? 1 : 5)
                                                    .fill(.white.opacity(n == 0 ? 0.95 : 0.38))
                                                    .frame(width: n == 0 ? 24 : 13, height: CGFloat(10 + ((n + index) % 3) * 6))
                                            }
                                        }.padding(9)
                                    }
                                if theme.animated { Image(systemName: "waveform.path").font(.caption.bold()).foregroundStyle(.white).padding(7) }
                                if isSelected { Image(systemName:"checkmark.circle.fill").font(.title3).foregroundStyle(.white).padding(7) }
                            }
                            Text(language == "ar" ? theme.ar : theme.en).font(.caption.weight(.bold)).foregroundStyle(.white).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(language == "ar" ? theme.layout : (theme.animated ? "Animated" : "Layout"))
                                    .font(.system(size: 9,weight:.medium)).foregroundStyle(theme.colors[0])
                                if theme.animated { Text("• حركة").font(.system(size: 9,weight:.bold)).foregroundStyle(.white.opacity(0.6)) }
                            }
                        }
                        .padding(8).frame(maxWidth:.infinity,alignment:.leading)
                        .background(isSelected ? theme.colors[0].opacity(0.18) : .white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: index % 4 == 0 ? 8 : 16))
                        .overlay(RoundedRectangle(cornerRadius: index % 4 == 0 ? 8 : 16).stroke(isSelected ? theme.colors[0] : .white.opacity(0.08),lineWidth:isSelected ? 1.6 : 1))
                    }.buttonStyle(.plain)
                }
            }
            Text(language == "ar" ? "كل ثيم يحفظ هويته وترتيب أقسام الصفحة الرئيسية. بعض الثيمات فيها حركة خفيفة، وتقدر توقفها من إعدادات الحركة." : "Each theme saves its own home layout. Selected themes include subtle motion.")
                .font(.caption2).foregroundStyle(.white.opacity(0.48))
        }
    }
}

private struct INRPFThemeSurface: ViewModifier {
    let themeIndex: Int
    let tint: Color
    func body(content: Content) -> some View {
        let radius: CGFloat = [26,18,12,22,9][themeIndex % 5]
        content
            .padding(.vertical, themeIndex % 4 == 0 ? 1 : 0)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(tint.opacity(themeIndex % 3 == 0 ? 0.20 : 0.09),
                            style: StrokeStyle(lineWidth: themeIndex % 5 == 3 ? 1.5 : 0.8,
                                               dash: themeIndex % 5 == 2 ? [4,3] : []))
                    .allowsHitTesting(false)
            }
            .shadow(color: tint.opacity(themeIndex % 5 == 1 ? 0.09 : 0.025), radius: themeIndex % 5 == 1 ? 13 : 5, y: 3)
    }
}

private struct AppSettingsView: View {
    @AppStorage("gta_show_hidden_files") private var showHiddenFiles = false
    @AppStorage("gta_language") private var language = "ar"
    @AppStorage("gta_accent_color") private var accent = "purple"
    @AppStorage("gta_background_color") private var background = "midnight"
    @AppStorage("gta_welcome_message") private var welcome = "حيّاك في GTA Converter"
    @AppStorage("gta_motion_enabled") private var motionEnabled = true
    @AppStorage("gta_home_density") private var homeDensity = "comfortable"
    @AppStorage("gta_onboarding_complete") private var onboardingComplete = false
    @State private var cacheMessage = ""

    private var tint: Color {
        switch accent {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red", "crimson": return Color(red: 0.88, green: 0.12, blue: 0.25)
        case "cyan": return Color(red: 0.10, green: 0.82, blue: 0.95)
        case "pink": return Color(red: 0.96, green: 0.28, blue: 0.65)
        case "teal": return Color(red: 0.08, green: 0.72, blue: 0.67)
        case "gold": return Color(red: 0.91, green: 0.67, blue: 0.18)
        case "ice": return Color(red: 0.55, green: 0.78, blue: 1.0)
        case "lime": return Color(red: 0.58, green: 0.82, blue: 0.20)
        case "violet": return Color(red: 0.42, green: 0.20, blue: 0.85)
        default: return .purple
        }
    }

    var body: some View {
        ZStack {
            GTASetupBackground(style: background).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape.2.fill").font(.system(size: 30)).foregroundStyle(tint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language == "ar" ? "إعدادات التطبيق" : "App Settings").font(.title3.bold()).foregroundStyle(.white)
                            Text(language == "ar" ? "غيّر خياراتك بأي وقت" : "Change your preferences anytime").font(.caption).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                    }.padding(18).background(LinearGradient(colors: [tint.opacity(0.3), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    group(language == "ar" ? "اللغة" : "Language", icon: "globe") {
                        Picker(language == "ar" ? "لغة التطبيق" : "App language", selection: $language) {
                            Text("العربية").tag("ar")
                            Text("English").tag("en")
                        }.pickerStyle(.segmented)
                    }
                    group(language == "ar" ? "أيقونة التطبيق" : "App icon", icon: "app.fill") {
                        AppIconPickerView(language: language, tint: tint)
                    }
                    group(language == "ar" ? "ثيمات وتصاميم التطبيق" : "App themes & designs", icon: "swatchpalette.fill") {
                        INRPFThemePickerView(language: language)
                    }
                    group(language == "ar" ? "التصميم" : "Appearance", icon: "paintpalette.fill") {
                        Text(language == "ar" ? "لون الواجهة" : "Accent color").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        Picker(language == "ar" ? "اللون" : "Color", selection: $accent) {
                            Text(language == "ar" ? "بنفسجي" : "Purple").tag("purple")
                            Text(language == "ar" ? "أزرق" : "Blue").tag("blue")
                            Text(language == "ar" ? "أخضر" : "Green").tag("green")
                            Text(language == "ar" ? "برتقالي" : "Orange").tag("orange")
                            Text(language == "ar" ? "أحمر" : "Red").tag("red")
                        }.pickerStyle(.menu).tint(tint)
                        Divider().overlay(.white.opacity(0.1))
                        Text(language == "ar" ? "خلفية التطبيق" : "App background").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        Picker(language == "ar" ? "الخلفية" : "Background", selection: $background) {
                            Text(language == "ar" ? "ليلي" : "Midnight").tag("midnight")
                            Text(language == "ar" ? "أسود" : "Black").tag("black")
                            Text(language == "ar" ? "كحلي" : "Navy").tag("navy")
                            Text(language == "ar" ? "فحمي" : "Graphite").tag("graphite")
                        }.pickerStyle(.menu).tint(tint)
                    }
                    group(language == "ar" ? "رسالة الترحيب" : "Welcome message", icon: "hand.wave.fill") {
                        TextField(language == "ar" ? "اكتب رسالة الترحيب" : "Enter your welcome message", text: $welcome, axis: .vertical)
                            .lineLimit(2...4).padding(12).background(.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                        Text(language == "ar" ? "تقدر تعدّل العبارة هنا بأي وقت." : "You can edit this message here at any time.")
                            .font(.caption).foregroundStyle(.white.opacity(0.55))
                        Button { onboardingComplete = false } label: {
                            Label(language == "ar" ? "إعادة عرض شاشة البداية عند التشغيل القادم" : "Show onboarding on next launch", systemImage: "rectangle.on.rectangle")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(12)
                                .background(tint.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                        }
                    }
                    group(language == "ar" ? "الحركة وطريقة العرض" : "Motion & layout", icon: "sparkles") {
                        Toggle(language == "ar" ? "تفعيل الانتقالات والحركة" : "Enable transitions and motion", isOn: $motionEnabled).tint(tint).foregroundStyle(.white)
                        Picker(language == "ar" ? "كثافة الواجهة" : "Home layout density", selection: $homeDensity) {
                            Text(language == "ar" ? "مريحة" : "Comfortable").tag("comfortable")
                            Text(language == "ar" ? "مضغوطة" : "Compact").tag("compact")
                        }.pickerStyle(.segmented)
                    }
                    group(language == "ar" ? "عام" : "General", icon: "slider.horizontal.3") {
                        Toggle(isOn: $showHiddenFiles) {
                            Label(language == "ar" ? "إظهار الملفات المخفية" : "Show hidden files", systemImage: "eye").foregroundStyle(.white)
                        }.tint(tint)
                    }
                    group(language == "ar" ? "التخزين" : "Storage", icon: "internaldrive") {
                        Label(language == "ar" ? "مجلد التطبيق" : "App storage", systemImage: "folder.fill").foregroundStyle(.white)
                        Text(language == "ar" ? "تخزين داخلي خاص بالتطبيق، غير ظاهر في تطبيق الملفات" : "Private app storage, not visible in the Files app").font(.caption).foregroundStyle(.white.opacity(0.55))
                        Button {
                            do {
                                let temp = FileManager.default.temporaryDirectory
                                let contents = try FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
                                for item in contents where item.lastPathComponent.hasPrefix("GTA-") { try? FileManager.default.removeItem(at: item) }
                                cacheMessage = language == "ar" ? "تم تنظيف الملفات المؤقتة." : "Temporary files cleared."
                            } catch { cacheMessage = error.localizedDescription }
                        } label: {
                            Label(language == "ar" ? "تنظيف الملفات المؤقتة" : "Clear temporary files", systemImage: "trash")
                                .frame(maxWidth: .infinity).padding(12).background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                        }
                        if !cacheMessage.isEmpty { Text(cacheMessage).font(.caption).foregroundStyle(.white.opacity(0.65)) }
                    }
                    group(language == "ar" ? "حول التطبيق" : "About", icon: "info.circle") {
                        settingRow(language == "ar" ? "اسم التطبيق" : "App name", "INRPF")
                        settingRow(language == "ar" ? "النظام الأدنى" : "Minimum iOS", "iOS 16+")
                    }
                    group(language == "ar" ? "الخصوصية" : "Privacy", icon: "lock.shield") {
                        Text(language == "ar" ? "ملفاتك تحفظ محلياً داخل التطبيق ولا يتم رفعها إلى خادم خارجي." : "Your files stay locally in the app and are not uploaded to an external server.")
                            .font(.caption).foregroundStyle(.white.opacity(0.62))
                    }
                    HStack {
                        Text(language == "ar" ? "الإصدار" : "Version").foregroundStyle(.white.opacity(0.65))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.90")
                            .font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(.white)
                    }.padding(16).frame(maxWidth: .infinity).background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 15))
                }.padding(16)
            }
        }
        .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: language))
        .navigationTitle(language == "ar" ? "الإعدادات" : "Settings")
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
        HStack { Text(title).foregroundStyle(.white.opacity(0.7)); Spacer(); Text(value).foregroundStyle(.white) }.font(.subheadline)
    }
}

private struct HomeMenuCustomizationView: View {
    @AppStorage("inrpf_home_menu_order") private var storedOrder = ""
    @AppStorage("inrpf_home_menu_style") private var menuStyle = "pill"
    @AppStorage("inrpf_home_menu_position") private var menuPosition = "top"
    @State private var order = [
        "engine", "fivem", "ftp", "orbx", "rpf", "cloud", "browser", "library",
        "downloads", "history", "ytd", "setup", "features", "files", "settings",
        "diagnostics", "creator", "customize"
    ]
    private let labels: [(String, String)] = [
        ("engine", "المحرك المحلي"), ("fivem", "استوديو FiveM"), ("ftp", "FTP جهاز PS4"),
        ("orbx", "إرسال تلقائي للسوني"), ("rpf", "محرر RPF"), ("cloud", "التحويل السحابي"),
        ("browser", "متصفح المودات"), ("library", "مكتبة المودات"), ("downloads", "التنزيلات"),
        ("history", "سجل العمليات"), ("ytd", "محرر YTD"), ("setup", "التخصيص واللغة"),
        ("features", "الميزات"), ("files", "ملفاتي"), ("settings", "الإعدادات"),
        ("diagnostics", "استكشاف المشاكل وحلها"), ("creator", "المبدع"), ("customize", "ترتيب القوائم")
    ]

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("خصص شكل القائمة الرئيسية ورتّب اختصاراتك بأزرار الأعلى والأسفل.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    VStack(alignment: .leading, spacing: 9) {
                        Text("شكل القوائم").font(.headline).foregroundStyle(.white)
                        Picker("شكل القوائم", selection: $menuStyle) {
                            Text("كبسولات").tag("pill")
                            Text("بطاقات").tag("card")
                            Text("بسيط").tag("minimal")
                            Text("قائمة").tag("list")
                        }.pickerStyle(.segmented).tint(.purple)
                    }.padding(15).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 9) {
                        Text("مكان القائمة الرئيسية").font(.headline).foregroundStyle(.white)
                        Picker("مكان القائمة", selection: $menuPosition) {
                            Text("تحت العنوان").tag("top")
                            Text("بعد التحويل").tag("afterConversion")
                            Text("بعد الاستيراد").tag("afterImport")
                        }.pickerStyle(.segmented).tint(.purple)
                    }.padding(15).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 15))
                    ForEach(order.indices, id: \.self) { index in
                        let id = order[index]
                        HStack(spacing: 10) {
                            Text(labels.first(where: { $0.0 == id })?.1 ?? id)
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Spacer()
                            Button { move(index, by: -1) } label: {
                                Image(systemName: "arrow.up").frame(width: 34, height: 34)
                            }.disabled(index == 0)
                            Button { move(index, by: 1) } label: {
                                Image(systemName: "arrow.down").frame(width: 34, height: 34)
                            }.disabled(index == order.count - 1)
                        }.padding(11).background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button("استعادة الترتيب الافتراضي") {
                        order = labels.map(\.0)
                        save()
                    }.font(.subheadline.bold()).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(13)
                        .background(Color.purple.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 12))
                }.padding(16)
            }
        }
        .navigationTitle("تخصيص القائمة الرئيسية")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            let saved = storedOrder.split(separator: ",").map(String.init)
            let validIDs = Set(labels.map { $0.0 })
            let valid = saved.filter { validIDs.contains($0) }
            if !valid.isEmpty { order = valid + labels.map(\.0).filter { !valid.contains($0) } }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard order.indices.contains(index), order.indices.contains(target) else { return }
        order.swapAt(index, target)
        save()
    }

    private func save() { storedOrder = order.joined(separator: ",") }
}
