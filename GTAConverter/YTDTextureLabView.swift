import SwiftUI
import UniformTypeIdentifiers

struct YTDTextureLabView: View {
    @State private var showingPicker = false
    @State private var reports: [YTDFileReport] = []
    @State private var status = "اختر ملفات YTD لفحصها والتأكد من سلامة ترويسة RAGE Resource."
    @State private var isError = false

    private let purple = Color(red: 0.60, green: 0.31, blue: 0.98)
    private let background = Color(red: 0.035, green: 0.025, blue: 0.065)

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    VStack(alignment: .leading, spacing: 9) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 34)).foregroundStyle(purple)
                        Text("مختبر ملفات YTD")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("فحص ملفات Texture Dictionary والتأكد من ترويسة RSC7 قبل إرسالها لمسار المعالجة.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    Button { showingPicker = true } label: {
                        Label("اختيار ملفات YTD", systemImage: "doc.badge.plus")
                            .font(.headline.bold()).frame(maxWidth: .infinity).padding(16)
                            .background(purple).clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }

                    if !reports.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("نتائج الفحص: \(reports.count)", systemImage: "waveform.path")
                                .font(.headline).foregroundStyle(.white)
                            ForEach(reports) { report in
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Image(systemName: report.isRSC7 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                            .foregroundStyle(report.isRSC7 ? .green : .orange)
                                        Text(report.name).font(.subheadline.bold()).foregroundStyle(.white)
                                            .lineLimit(2)
                                    }
                                    HStack {
                                        Text(report.sizeText)
                                        Spacer()
                                        Text(report.signature)
                                    }
                                    .font(.caption.monospaced()).foregroundStyle(.white.opacity(0.58))
                                    Text(report.isRSC7
                                         ? "تم التعرف على ترويسة RSC7. هذا فحص أولي وليس إثباتاً أن الخامات قابلة للتحويل."
                                         : "لم يتم التعرف على ترويسة RSC7؛ قد يكون الملف تالفاً أو بصيغة مختلفة.")
                                        .font(.caption).foregroundStyle(.white.opacity(0.68))
                                }
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.black.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(15).background(.white.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }

                    NavigationLink(destination: CloudConversionView()) {
                        Label("فتح أدوات المعالجة السحابية", systemImage: "cloud.gear.fill")
                            .font(.headline.bold()).frame(maxWidth: .infinity).padding(15)
                            .background(.white.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("وش يسوي هذا القسم؟", systemImage: "info.circle.fill")
                            .font(.subheadline.bold()).foregroundStyle(.orange)
                        Text("يفحص امتداد الملف وحجمه وترويسة RSC7 فقط. لا يستخرج صور DDS ولا يعيد بناء YTD أو يحوّله إلى PS4 محلياً. استخدم مسار المعالجة السحابية لتنفيذ أدوات YTD الموجودة في محرك Ps4tools، وتحقق من سجل التشغيل والناتج قبل استخدامه.")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(14).background(.orange.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    Text(status)
                        .font(.caption).foregroundStyle(isError ? .red : .white.opacity(0.65))
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
        }
        .navigationTitle("YTD")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, .rightToLeft)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            inspectFiles(result)
        }
    }

    private func inspectFiles(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            var found: [YTDFileReport] = []
            for url in urls where url.pathExtension.lowercased() == "ytd" {
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let header = try handle.read(upToCount: 16) ?? Data()
                let signature = String(data: header.prefix(4), encoding: .ascii) ?? "غير معروف"
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                found.append(YTDFileReport(
                    name: url.lastPathComponent,
                    bytes: bytes,
                    signature: signature,
                    isRSC7: signature == "RSC7"
                ))
            }
            reports = found
            isError = found.isEmpty
            status = found.isEmpty
                ? "ما اخترت أي ملف بامتداد YTD."
                : "اكتمل الفحص الأولي لـ \(found.count) ملف."
        } catch {
            isError = true
            status = "تعذر فحص الملفات: \(error.localizedDescription)"
        }
    }
}

private struct YTDFileReport: Identifiable {
    let id = UUID()
    let name: String
    let bytes: Int64
    let signature: String
    let isRSC7: Bool

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
