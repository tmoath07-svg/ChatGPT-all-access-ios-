import SwiftUI
import UniformTypeIdentifiers

struct RPFStudioView: View {
    @State private var selectedFile: URL?
    @State private var selectedFileName = "اختر ملف RPF"
    @State private var report = "اختر ملف dlc.rpf وسيبدأ Python تلقائياً."
    @State private var busy = false
    @State private var error = false
    @State private var importing = false

    private let purple = Color(red: 0.58, green: 0.31, blue: 0.98)
    private let background = Color(red: 0.035, green: 0.025, blue: 0.065)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    fileCard
                    Button(action: runInspection) {
                        Label(busy ? "جاري الفحص..." : "إعادة فحص الملف باستخدام Python",
                              systemImage: "waveform.path.ecg")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(purple.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .foregroundStyle(.white)
                    }
                    .disabled(selectedFile == nil || busy)
                    .opacity(selectedFile == nil || busy ? 0.5 : 1)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("تقرير المحرك", systemImage: "terminal")
                            .font(.headline)
                        Text(report)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .background(.black.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                    .padding(16)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    Text("الفاحص الحالي يقرأ بيانات الملف والترويسة والبصمة SHA256 فقط؛ لا يدّعي استخراج أو إعادة بناء RPF.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [UTType(filenameExtension: "rpf", conformingTo: .data) ?? .data, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    report = "لم يرجع تطبيق الملفات أي ملف."
                    error = true
                    return
                }
                selectedFile = url
                selectedFileName = url.lastPathComponent
                startInspection(for: url)
            case .failure(let issue):
                report = "تعذر اختيار الملف: \(issue.localizedDescription)"
                error = true
                busy = false
            }
        }
        .navigationTitle("RPF Studio")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(purple)
            Text("RPF STUDIO")
                .font(.system(size: 27, weight: .black, design: .rounded))
            Text("مختبر ملفات GTA V — تشغيل Python داخل INRPF")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(LinearGradient(colors: [purple.opacity(0.32), .white.opacity(0.035)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var fileCard: some View {
        Button {
            report = "تم الضغط على اختيار الملف — جارٍ فتح تطبيق «الملفات»..."
            error = false
            importing = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundStyle(purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedFileName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("اضغط هنا لاختيار ملف RPF من تطبيق «الملفات»")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.left")
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(16)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func runInspection() {
        guard let source = selectedFile else { return }
        startInspection(for: source)
    }

    private func startInspection(for source: URL) {
        guard !busy else { return }
        busy = true
        error = false
        report = "تم اختيار \(source.lastPathComponent)\nجارٍ فتح صلاحية الملف ونسخه وتشغيل Python..."

        // Start the security-scoped access while still in the picker callback/UI context.
        let scopeStarted = source.startAccessingSecurityScopedResource()
        Task.detached(priority: .userInitiated) {
            defer {
                if scopeStarted { source.stopAccessingSecurityScopedResource() }
            }
            do {
                // Keep the scope alive until the coordinated copy is complete.
                let local = try FileImportService.importItem(
                    from: source,
                    category: "RPFStudio",
                    securityScopeAlreadyStarted: scopeStarted
                )
                defer { try? FileManager.default.removeItem(at: local.deletingLastPathComponent()) }

                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: local.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    throw NSError(domain: "RPFStudio.Import", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "اختر ملف RPF عادي، وليس مجلداً."])
                }
                let copiedSize = try FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber
                guard copiedSize?.int64Value ?? 0 > 0 else {
                    throw NSError(domain: "RPFStudio.Import", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "الملف المستورد فارغ أو تعذرت قراءته."])
                }

                let result = try PythonRuntime.shared.inspect(file: local)
                await MainActor.run {
                    report = "نجح الاستيراد وتشغيل Python ✅\n\n" + result
                    error = false
                    busy = false
                }
            } catch {
                await MainActor.run {
                    report = "فشل الاستيراد أو تشغيل Python ❌\n\(error.localizedDescription)"
                    self.error = true
                    busy = false
                }
            }
        }
    }
}
