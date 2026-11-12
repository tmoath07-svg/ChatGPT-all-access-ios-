import SwiftUI
import UniformTypeIdentifiers

/// Local FiveM resource inspection. Conversion is only reported when a real
/// conversion workflow has produced and validated a package.
struct FiveMStudioView: View {
    @State private var showingFolderPicker = false
    @State private var report: ModAnalysisReport?
    @State private var status = "اختر مجلد مورد FiveM بعد فك ضغطه."
    @State private var isBusy = false
    @State private var errorText: String?

    private let workflowURL = URL(string: "https://github.com/tmoath07-svg/ChatGPT-all-access-ios-/actions/workflows/convert-pc-to-ps4.yml")!

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.025, blue: 0.065).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "car.side.3.fill").font(.system(size: 34)).foregroundStyle(.purple)
                        Text("FiveM Resource Studio").font(.title2.bold()).foregroundStyle(.white)
                        Text("فحص محلي لبنية موارد FiveM. الفحص لا يحوّل ملفات الكمبيوتر إلى PS4 بحد ذاته.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 18))

                    Button {
                        errorText = nil
                        showingFolderPicker = true
                    } label: {
                        Label(isBusy ? "جاري الفحص..." : "اختيار مجلد مورد FiveM", systemImage: "folder.badge.plus")
                            .font(.headline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(15)
                            .background(Color.purple.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                    .disabled(isBusy)

                    Text(status).font(.caption).foregroundStyle(.white.opacity(0.7))
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
                        Label("فتح محرك تحويل FiveM إلى DLC", systemImage: "arrow.up.right.square")
                            .font(.headline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(15)
                            .background(Color.orange.opacity(0.78))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                    }

                    Text("المسار السحابي يدعم موارد سيارات محددة ببنية stream/ وdata/ وملفات META المطلوبة. سكربتات Lua وواجهات NUI واعتماديات السيرفر لا تتحول تلقائياً إلى DLC.")
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
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderSelection(result)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(.white)
        }.font(.caption).padding(.vertical, 2)
    }

    private func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            errorText = "تعذر اختيار المجلد: \(error.localizedDescription)"
            status = "لم يتم استيراد أي مجلد."
        case .success(let urls):
            guard let source = urls.first else {
                status = "لم يتم اختيار مجلد."
                return
            }
            importAndAnalyze(source)
        }
    }

    private func importAndAnalyze(_ source: URL) {
        isBusy = true
        errorText = nil
        report = nil
        status = "يتم نسخ مجلد المورد إلى مساحة INRPF..."
        Task {
            do {
                let copy = try await Task.detached(priority: .userInitiated) {
                    try FileImportService.importItem(from: source, category: "FiveM")
                }.value
                status = "تم الاستيراد. يتم تحليل ملفات المورد..."
                let result = try await Task.detached(priority: .userInitiated) {
                    try ModAnalyzer.analyze(at: copy)
                }.value
                report = result
                status = "اكتمل الفحص: \(copy.lastPathComponent)"
            } catch {
                errorText = error.localizedDescription
                status = "تعذر استيراد أو فحص المجلد."
            }
            isBusy = false
        }
    }
}
