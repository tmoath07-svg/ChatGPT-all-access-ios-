import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LocalUtilityFeatureView: View {
    let featureID: Int

    @State private var showingPicker = false
    @State private var selectedName = ""
    @State private var resultText = ""
    @State private var hexText = ""
    @State private var nameInput = ""
    @State private var existingNames = ""
    @State private var shareURL: URL?
    @State private var isBusy = false

    private var pageTitle: String {
        switch featureID {
        case 4: "محرر Hex"
        case 30: "Auto DLC Naming"
        case 31: "Smart Folder"
        case 33: "Mod Report PDF"
        case 34: "مؤشر جاهزية PS4"
        case 35: "Mod Backup"
        case 37: "Dependency Checker"
        case 40: "دليل التركيب"
        default: "أدوات INRPF"
        }
    }

    private var pickerTypes: [UTType] {
        featureID == 4 ? [.data] : [.folder]
    }

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text(pageTitle).font(.title2.bold()).foregroundStyle(.white)
                    featureBody
                    if isBusy {
                        ProgressView("جاري التنفيذ محلياً...").tint(.purple).foregroundStyle(.white)
                    }
                    if !resultText.isEmpty {
                        Text(resultText).font(.caption).foregroundStyle(.white.opacity(0.8))
                            .textSelection(.enabled)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("مشاركة الملف الناتج", systemImage: "square.and.arrow.up")
                                .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(13)
                                .background(Color.purple).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.padding(16)
            }
        }
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: pickerTypes, allowsMultipleSelection: false) { handleImport($0) }
        .environment(\.layoutDirection, .rightToLeft)
    }

    @ViewBuilder private var featureBody: some View {
        switch featureID {
        case 4:
            hexEditor
        case 30:
            namingTool
        case 31:
            folderTool(
                description: "ينسخ الملفات إلى مجلد جديد مصنف حسب النوع. لا يغيّر المجلد الأصلي.",
                button: "اختر مجلد المود ورتّبه"
            )
        case 33:
            folderTool(
                description: "يفحص مجلد المود محلياً ثم ينشئ تقرير PDF قابل للمشاركة.",
                button: "اختر مجلد المود لإنشاء PDF"
            )
        case 34:
            folderTool(
                description: "يحسب مؤشراً بنيوياً من الملفات الموجودة. الدرجة ليست اختبار تشغيل على PS4.",
                button: "افحص جاهزية المجلد"
            )
        case 35:
            folderTool(
                description: "ينشئ نسخة مؤرخة من المجلد في مساحة التطبيق المؤقتة. لا يغيّر المصدر.",
                button: "اختر مجلد المود لنسخه احتياطياً"
            )
        case 37:
            folderTool(
                description: "يفحص dependency وملفات manifest ومراجع الملفات المحلية الشائعة.",
                button: "اختر مورد FiveM لفحص اعتمادياته"
            )
        case 40:
            installerGuide
        default:
            Text("الميزة غير متاحة.").foregroundStyle(.white)
        }
    }

    private var hexEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("اختر ملفاً ثنائياً. تظهر البايتات كقيم Hex ويمكنك تعديلها وحفظ نسخة منفصلة.")
                .font(.caption).foregroundStyle(.white.opacity(0.65))
            Button { showingPicker = true } label: {
                Label("اختيار ملف", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity).padding(12).background(.purple)
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if !selectedName.isEmpty {
                Text(selectedName).font(.caption.monospaced()).foregroundStyle(.purple)
            }
            TextEditor(text: $hexText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button("حفظ نسخة معدّلة") { saveHexCopy() }
                .disabled(hexText.isEmpty || isBusy)
                .frame(maxWidth: .infinity).padding(12)
                .background(.purple.opacity(0.8)).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var namingTool: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("اسم السيارة أو المود").font(.caption.bold()).foregroundStyle(.purple)
            TextField("مثال: BMW M5 Competition", text: $nameInput)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            Text("أسماء موجودة مسبقاً، افصل بينها بفاصلة (اختياري)").font(.caption).foregroundStyle(.white.opacity(0.6))
            TextField("bmw_m5, supra", text: $existingNames)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(.white.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
            Text("الاسم المقترح").font(.caption.bold()).foregroundStyle(.purple)
            Text(generatedPackageName).font(.title3.monospaced().bold()).foregroundStyle(.white)
            Button {
                UIPasteboard.general.string = generatedPackageName
                resultText = "تم نسخ الاسم: \(generatedPackageName)"
            } label: {
                Label("نسخ الاسم", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity).padding(12).background(.purple)
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func folderTool(description: String, button: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(description).font(.caption).foregroundStyle(.white.opacity(0.65))
            Button { showingPicker = true } label: {
                Label(button, systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity).padding(13).background(.purple)
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if !selectedName.isEmpty {
                Text(selectedName).font(.caption.monospaced()).foregroundStyle(.purple)
            }
        }
    }

    private var installerGuide: some View {
        VStack(alignment: .leading, spacing: 11) {
            guideStep("1", "تأكد من أن الحزمة تحتوي dlc.rpf مباشرة داخل مجلد اسم المود.")
            guideStep("2", "ضع مجلد الحزمة داخل /data/orbx/gta/rpf/dlc_addon/.")
            guideStep("3", "أضف مسار المجلد إلى Paths داخل dlclist.xml، مع المحافظة على الإدخالات السابقة.")
            guideStep("4", "أنشئ نسخة احتياطية من dlclist.xml قبل النقل.")
            guideStep("5", "انقل الملفات عبر FTP بعد التأكد من اتصال PS4 وصحة المسارات.")
            guideStep("6", "أعد تنزيل dlclist.xml وقارن بصمته ومحتواه بعد الرفع.")
            Text("تنبيه: وجود dlc.rpf لا يثبت أن محتواه متوافق مع PS4 أو أن المود سيعمل داخل اللعبة.")
                .font(.caption).foregroundStyle(.orange)
                .padding(11).background(.orange.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func guideStep(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 25, height: 25).background(.purple).clipShape(Circle())
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.82))
        }
    }

    private var generatedPackageName: String {
        let folded = nameInput.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let ascii = folded.unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            if (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value) || value == 45 || value == 95 {
                return Character(scalar)
            }
            return "_"
        }
        var base = String(ascii).replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        if base.isEmpty { base = "dlc_pack" }
        base = String(base.prefix(48))
        let existing = Set(existingNames.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if !existing.contains(base.lowercased()) { return base }
        var suffix = 2
        while existing.contains("\(base)_\(suffix)".lowercased()) { suffix += 1 }
        return "\(base)_\(suffix)"
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        selectedName = url.lastPathComponent
        resultText = ""
        shareURL = nil
        isBusy = true

        Task { @MainActor in
            do {
                if featureID == 4 {
                    let data = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                        guard size <= 512 * 1024 else {
                            throw NSError(domain: "INRPF.Hex", code: 1, userInfo: [NSLocalizedDescriptionKey: "الحد الأقصى لمحرر Hex هو 512KB."])
                        }
                        return try Data(contentsOf: url)
                    }.value
                    hexText = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                    resultText = "تم تحميل \(data.count) بايت. عدّل القيم واحفظ نسخة جديدة."
                } else if featureID == 31 {
                    let output = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        return try INRPFLocalUtilities.createSortedCopy(of: url)
                    }.value
                    shareURL = output.url
                    resultText = "تم نسخ \(output.count) ملف إلى مجلد مصنف. المصدر لم يتغير."
                } else if featureID == 33 {
                    let report = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        return try ModAnalyzer.analyze(at: url)
                    }.value
                    let pdf = try INRPFLocalUtilities.createPDF(report: report.reportText)
                    shareURL = pdf
                    resultText = "تم إنشاء تقرير PDF من \(report.fileCount) ملف."
                } else if featureID == 34 {
                    let report = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        return try ModAnalyzer.analyze(at: url)
                    }.value
                    let score = INRPFLocalUtilities.structuralScore(report)
                    resultText = "مؤشر الجاهزية البنيوية: \(score)/100\n\(report.reportText)\n\nهذه الدرجة لا تعني ضمان التوافق أو التشغيل على PS4."
                } else if featureID == 35 {
                    let backup = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        return try INRPFLocalUtilities.createBackup(of: url)
                    }.value
                    shareURL = backup
                    resultText = "تم إنشاء نسخة احتياطية مستقلة باسم \(backup.lastPathComponent)."
                } else if featureID == 37 {
                    let report = try await Task.detached(priority: .userInitiated) {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        return try INRPFLocalUtilities.dependencyReport(at: url)
                    }.value
                    resultText = report
                }
            } catch {
                resultText = "تعذر إكمال العملية: \(error.localizedDescription)"
            }
            isBusy = false
        }
    }

    private func saveHexCopy() {
        let tokens = hexText.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty, tokens.count <= 512 * 1024 else {
            resultText = "أدخل بايتات Hex صحيحة ضمن حد 512KB."
            return
        }
        var bytes = [UInt8]()
        for token in tokens {
            guard token.count == 2, let byte = UInt8(token, radix: 16) else {
                resultText = "صيغة غير صحيحة عند القيمة: \(token). استخدم بايتين Hex مثل FF أو 0A."
                return
            }
            bytes.append(byte)
        }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("INRPF-Hex-Edited-\(UUID().uuidString).bin")
            try Data(bytes).write(to: url, options: .atomic)
            shareURL = url
            resultText = "تم حفظ نسخة معدّلة من \(bytes.count) بايت. الملف الأصلي لم يتغير."
        } catch {
            resultText = "تعذر حفظ النسخة: \(error.localizedDescription)"
        }
    }
}

private enum INRPFLocalUtilities {
    static func createSortedCopy(of source: URL) throws -> (url: URL, count: Int) {
        let fm = FileManager.default
        let output = fm.temporaryDirectory.appendingPathComponent("INRPF-Sorted-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "INRPF.Sort", code: 1, userInfo: [NSLocalizedDescriptionKey: "تعذر قراءة المجلد."])
        }
        var count = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let relative = String(file.path.dropFirst(source.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else { continue }
            let category: String
            switch file.pathExtension.lowercased() {
            case "yft", "ydr", "ybn", "ydd": category = "Models"
            case "ytd", "dds", "png", "jpg", "jpeg": category = "Textures"
            case "meta", "xml": category = "Metadata"
            case "lua", "js", "html", "css": category = "Scripts"
            case "rpf", "zip", "rar", "7z": category = "Archives"
            default: category = "Other"
            }
            let destination = output.appendingPathComponent(category, isDirectory: true).appendingPathComponent(relative)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: destination)
            count += 1
        }
        return (output, count)
    }

    static func createBackup(of source: URL) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("INRPF-Backup-\(stamp)", isDirectory: true)
        try FileManager.default.copyItem(at: source, to: output)
        return output
    }

    static func createPDF(report: String) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let lines = report.components(separatedBy: .newlines)
        let data = renderer.pdfData { context in
            context.beginPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.black
            ]
            var y: CGFloat = 36
            for line in lines {
                if y > 748 {
                    context.beginPage()
                    y = 36
                }
                NSString(string: line).draw(at: CGPoint(x: 36, y: y), withAttributes: attributes)
                y += 13
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("INRPF-Report-\(UUID().uuidString).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func structuralScore(_ report: ModAnalysisReport) -> Int {
        var score = 0
        if !report.dlcFiles.isEmpty { score += 20 }
        if !report.yftFiles.isEmpty { score += 15 }
        if !report.ytdFiles.isEmpty { score += 15 }
        if report.vehicleMetaFiles.contains(where: { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "vehicles.meta" }) { score += 15 }
        if report.vehicleMetaFiles.contains(where: { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "handling.meta" }) { score += 10 }
        if report.vehicleMetaFiles.contains(where: { URL(fileURLWithPath: $0).lastPathComponent.lowercased() == "carvariations.meta" }) { score += 10 }
        if !report.manifestFiles.isEmpty { score += 10 }
        if report.duplicatePackNames.isEmpty { score += 5 }
        return min(100, score)
    }

    static func dependencyReport(at root: URL) throws -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "INRPF.Dependency", code: 1, userInfo: [NSLocalizedDescriptionKey: "تعذر قراءة مجلد المورد."])
        }
        var manifests: [URL] = []
        for case let file as URL in enumerator where ["fxmanifest.lua", "__resource.lua"].contains(file.lastPathComponent.lowercased()) {
            manifests.append(file)
        }
        guard !manifests.isEmpty else {
            return "لم يتم العثور على fxmanifest.lua أو __resource.lua. لا يمكن استنتاج اعتماديات FiveM من المجلد وحده."
        }
        var dependencies = Set<String>()
        var localReferences = Set<String>()
        for manifest in manifests {
            let values = try manifest.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 2 * 1024 * 1024 else { continue }
            let text = try String(contentsOf: manifest, encoding: .utf8)
            dependencies.formUnion(captures(#"dependency\s*\(?\s*['"]([^'"]+)['"]"#, in: text))
            for block in captures(#"dependencies\s*\{([^}]*)\}"#, in: text) {
                localReferences.formUnion(captures(#"['"]([^'"]+)['"]"#, in: block))
            }
            for block in captures(#"(?:files|client_scripts|server_scripts|shared_scripts)\s*\{([^}]*)\}"#, in: text) {
                localReferences.formUnion(captures(#"['"]([^'"]+)['"]"#, in: block))
            }
            localReferences.formUnion(captures(#"(?:client_script|server_script|shared_script|ui_page)\s+['"]([^'"]+)['"]"#, in: text))
        }
        var missing: [String] = []
        for path in localReferences.sorted() {
            if path.hasPrefix("@") || path.contains("*") || path.hasPrefix("http") { continue }
            let candidate = root.appendingPathComponent(path).standardizedFileURL
            let rootPath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
            guard candidate.path.hasPrefix(rootPath) else {
                missing.append("\(path) (مسار خارج المورد)")
                continue
            }
            if !fm.fileExists(atPath: candidate.path) { missing.append(path) }
        }
        return [
            "DEPENDENCY CHECK",
            "ملفات manifest: \(manifests.count)",
            "اعتماديات خارجية معلنة: \(dependencies.count)",
            dependencies.sorted().map { "dependency: \($0)" }.joined(separator: "\n"),
            "مراجع ملفات محلية: \(localReferences.count)",
            "مراجع غير موجودة أو خارج المورد: \(missing.count)",
            missing.isEmpty ? "لم يتم العثور على مراجع مفقودة ضمن الأنماط المدعومة." : missing.joined(separator: "\n")
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return source.substring(with: match.range(at: 1))
        }
    }
}
