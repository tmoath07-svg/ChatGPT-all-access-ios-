import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedFile: URL?
    @State private var report = "اختر ملف dlc.rpf لبدء الفحص."
    @State private var busy = false
    @State private var error = false
    @State private var importing = false

    private let purple = Color(red: 0.58, green: 0.31, blue: 0.98)
    private let background = Color(red: 0.035, green: 0.025, blue: 0.065)

    var body: some View {
        NavigationStack {
            ZStack {
                background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        fileCard
                        Button(action: runInspection) {
                            Label(busy ? "جاري الفحص..." : "فحص ملف RPF باستخدام Python",
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
                        Text("الإصدار الأول: تشغيل Python وفحص أولي للملف. لا يدّعي هذا الإصدار استخراج أو تحويل RPF.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("RPF Studio")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    selectedFile = url
                    report = "تم اختيار: \(url.lastPathComponent)\nاضغط زر الفحص لتشغيل Python."
                    error = false
                case .failure(let issue):
                    report = "تعذر اختيار الملف: \(issue.localizedDescription)"
                    error = true
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(purple)
            Text("RPF STUDIO")
                .font(.system(size: 27, weight: .black, design: .rounded))
            Text("مختبر ملفات GTA V — تشغيل Python على iOS")
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
        Button { importing = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundStyle(purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedFile?.lastPathComponent ?? "اختر ملف RPF")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("الاختيار من تطبيق «الملفات»")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: "chevron.left")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(16)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func runInspection() {
        guard let source = selectedFile else { return }
        busy = true
        report = "يتم تجهيز Python وفحص الملف..."
        Task.detached(priority: .userInitiated) {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            do {
                let local = FileManager.default.temporaryDirectory
                    .appendingPathComponent("RPF-\(UUID().uuidString).rpf")
                try FileManager.default.copyItem(at: source, to: local)
                let result = try PythonRuntime.shared.inspect(file: local)
                await MainActor.run {
                    report = result
                    error = false
                    busy = false
                }
            } catch {
                await MainActor.run {
                    report = error.localizedDescription
                    self.error = true
                    busy = false
                }
            }
        }
    }
}
