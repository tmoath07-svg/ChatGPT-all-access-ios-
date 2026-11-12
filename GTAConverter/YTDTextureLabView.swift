import SwiftUI
import UniformTypeIdentifiers

struct YTDTextureLabView: View {
    @State private var showingPicker = false
    @State private var pickerMode: PickerMode = .ytd
    @State private var selectedYTDName = ""
    @State private var extractedFolder: URL?
    @State private var rebuiltYTD: URL?
    @State private var status = "اختر ملف YTD لاستخراج خاماته، أو مجلد DDS لإعادة بناء قاموس."
    @State private var isBusy = false
    @State private var isError = false

    @AppStorage("gta_language") private var appLanguage = "ar"
    private let purple = Color(red: 0.60, green: 0.31, blue: 0.98)

    private enum PickerMode {
        case ytd
        case ddsFolder
    }

    private var pickerTypes: [UTType] {
        pickerMode == .ddsFolder ? [.folder] : [.item]
    }

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 34)).foregroundStyle(purple)
                        Text("محرر ملفات YTD")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("استخرج الخامات إلى DDS، عدّل الصور في أي محرر صور، ثم أعد بناء قاموس YTD من مجلد الخامات.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    Button {
                        pickerMode = .ytd
                        showingPicker = true
                    } label: {
                        Label("فتح YTD واستخراج الخامات إلى DDS", systemImage: "archivebox")
                            .font(.headline.bold()).frame(maxWidth: .infinity).padding(16)
                            .background(purple).clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)

                    Button {
                        pickerMode = .ddsFolder
                        showingPicker = true
                    } label: {
                        Label("إعادة بناء YTD من مجلد DDS", systemImage: "square.stack.3d.up.fill")
                            .font(.headline.bold()).frame(maxWidth: .infinity).padding(16)
                            .background(.white.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)

                    if !selectedYTDName.isEmpty {
                        infoCard(title: "ملف المصدر", value: selectedYTDName, icon: "doc")
                    }

                    if let extractedFolder {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("تم استخراج الخامات", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(extractedFolder.lastPathComponent)
                                .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.65))
                            ShareLink(item: extractedFolder) {
                                Label("مشاركة مجلد DDS", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(12)
                                    .background(.white.opacity(0.09))
                                    .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                            }
                        }
                        .padding(15).background(.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                    }

                    if let rebuiltYTD {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("تم بناء قاموس YTD", systemImage: "checkmark.seal.fill")
                                .font(.headline).foregroundStyle(.green)
                            Text(rebuiltYTD.lastPathComponent)
                                .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.65))
                            ShareLink(item: rebuiltYTD) {
                                Label("مشاركة ملف YTD", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(12)
                                    .background(.white.opacity(0.09))
                                    .clipShape(RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                            }
                        }
                        .padding(15).background(.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                    }

                    if isBusy {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("جاري تنفيذ العملية محلياً...")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        }
                        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text(status)
                        .font(.caption).foregroundStyle(isError ? .red : .white.opacity(0.68))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 8) {
                        Label("ملاحظة الصيغة", systemImage: "info.circle.fill")
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                        Text("استخراج DDS وإعادة بناء YTD متاحان عبر المحرك المحلي. البناء الحالي ينتج YTD بصيغة PC/Gen8، ولا ينتج OTD بصيغة Orbis الخاصة بـ PS4.")
                            .font(.caption).foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(14).background(.orange.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(16)
            }
        }
        .navigationTitle("محرر YTD")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, appLanguage == "ar" ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: appLanguage))
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: pickerTypes, allowsMultipleSelection: false) { result in
            handlePicker(result)
        }
    }

    private func infoCard(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(purple)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.white.opacity(0.55))
                Text(value).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(2)
            }
            Spacer()
        }
        .padding(13).background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func handlePicker(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            isError = true
            status = "تعذر اختيار العنصر: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            if pickerMode == .ytd {
                extractTextures(from: url)
            } else {
                rebuildDictionary(from: url)
            }
        }
    }

    nonisolated private static func appSupportFolder(_ components: String...) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = components.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func extractTextures(from file: URL) {
        guard file.pathExtension.lowercased() == "ytd" else {
            isError = true
            status = "اختر ملفاً بامتداد YTD."
            return
        }
        let access = file.startAccessingSecurityScopedResource()
        isBusy = true
        isError = false
        selectedYTDName = file.lastPathComponent
        extractedFolder = nil
        Task.detached(priority: .userInitiated) {
            defer { if access { file.stopAccessingSecurityScopedResource() } }
            do {
                let base = try Self.appSupportFolder("GTA Converter", "YTD Editor", "Extracted")
                let output = base.appendingPathComponent(file.deletingPathExtension().lastPathComponent, isDirectory: true)
                let result = try LocalEngineBridge.extractYTD(at: file, to: output)
                await MainActor.run {
                    extractedFolder = output
                    let found = result["textures_found"] as? Int ?? 0
                    let exported = result["textures_exported"] as? Int ?? 0
                    status = "اكتمل الاستخراج: \(exported) من أصل \(found) خامة. عدّل ملفات DDS ثم أعد بناء القاموس."
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    isError = true
                    status = "فشل استخراج YTD: \(error.localizedDescription)"
                    isBusy = false
                }
            }
        }
    }

    private func rebuildDictionary(from folder: URL) {
        let access = folder.startAccessingSecurityScopedResource()
        isBusy = true
        isError = false
        rebuiltYTD = nil
        Task.detached(priority: .userInitiated) {
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            do {
                let base = try Self.appSupportFolder("GTA Converter", "YTD Editor", "Built")
                let safeName = folder.lastPathComponent.replacingOccurrences(of: "/", with: "_")
                let output = base.appendingPathComponent("\(safeName).ytd")
                let result = try LocalEngineBridge.buildYTD(from: folder, to: output)
                await MainActor.run {
                    rebuiltYTD = output
                    let textures = result["textures"] as? Int ?? 0
                    status = "اكتمل بناء YTD ويحتوي \(textures) خامة. تحقق من توافق الصيغة قبل استخدامها."
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    isError = true
                    status = "فشل بناء YTD: \(error.localizedDescription)"
                    isBusy = false
                }
            }
        }
    }
}
