import SwiftUI
import SwiftArchive
import UniformTypeIdentifiers
import UIKit

struct AppDiagnosticsView: View {
    let sourceURL: URL?
    let outputFolder: URL?
    let latestError: String

    @State private var report = "اضغط «بدء التحليل» لفحص الملف ومسار التحويل."
    @State private var isRunning = false
    @State private var passed = false

    private let purple = Color(red: 0.57, green: 0.30, blue: 0.98)
    private let background = Color(red: 0.035, green: 0.025, blue: 0.065)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("تحليل التشغيل والتحويل", systemImage: "waveform.path.ecg")
                            .font(.title3.bold()).foregroundStyle(.white)
                        Text("يفحص الملف قبل الفك، ويتحقق من بنية الأرشيف ومساراته وعدد الملفات، بدون تعديل الملف الأصلي.")
                            .font(.caption).foregroundStyle(.white.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18).background(purple.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    infoRow("الملف المحدد", sourceURL?.lastPathComponent ?? "لم يتم اختيار ملف")
                    infoRow("مجلد الناتج", outputFolder?.lastPathComponent ?? "لم يبدأ التحويل")

                    Button(action: runAnalysis) {
                        HStack {
                            if isRunning { ProgressView().tint(.white) }
                            Label(isRunning ? "جاري التحليل..." : "بدء التحليل", systemImage: "stethoscope")
                        }
                        .font(.headline).frame(maxWidth: .infinity).padding(15)
                        .background(purple).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isRunning || sourceURL == nil)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("نتيجة الفحص", systemImage: "doc.text.magnifyingglass")
                                .font(.headline).foregroundStyle(.white)
                            Spacer()
                            Text(passed ? "سليم" : "بانتظار الفحص")
                                .font(.caption.bold())
                                .foregroundStyle(passed ? .green : .orange)
                        }
                        Text(report).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.82))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = report
                        } label: {
                            Label("نسخ تقرير التحليل", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity).padding(11)
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                .foregroundStyle(.white)
                        }
                    }.padding(16).background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 17))

                    if !latestError.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("آخر خطأ", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline).foregroundStyle(.red)
                            Text(latestError).font(.caption).foregroundStyle(.white.opacity(0.78))
                                .textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = latestError
                            } label: {
                                Label("نسخ الخطأ وسببه", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity).padding(11)
                                    .background(.red.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 11))
                                    .foregroundStyle(.white)
                            }
                        }.padding(16).background(.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 17))
                    }
                }.padding(16)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationTitle("التشخيص")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).foregroundStyle(.white).lineLimit(1)
        }.font(.caption).padding(13)
            .background(.white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func runAnalysis() {
        guard let sourceURL else { return }
        isRunning = true
        report = "جاري فحص الملف..."
        Task.detached(priority: .userInitiated) {
            let result = await Self.inspect(sourceURL)
            await MainActor.run {
                report = result.text
                passed = result.passed
                isRunning = false
            }
        }
    }

    private static func inspect(_ url: URL) async -> (passed: Bool, text: String) {
        let fm = FileManager.default
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let size = values?.fileSize ?? 0
        var lines = [
            "GTA CONVERTER DIAGNOSTIC",
            "الاسم: \(url.lastPathComponent)",
            "الحجم: \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))",
            "المسار: \(url.path)"
        ]

        if values?.isDirectory == true {
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
                return (false, (lines + ["النتيجة: فشل فتح المجلد", "السبب: لا يمكن قراءة محتويات المجلد أو لا توجد صلاحية وصول."]).joined(separator: "\n"))
            }
            var files = 0
            var folders = 0
            var bytes: Int64 = 0
            while let item = enumerator.nextObject() as? URL {
                let v = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if v?.isDirectory == true { folders += 1 }
                else { files += 1; bytes += Int64(v?.fileSize ?? 0) }
                if files + folders > 20_000 {
                    return (false, (lines + ["النتيجة: تجاوز الحد", "السبب: المجلد يحتوي أكثر من 20,000 عنصر."]).joined(separator: "\n"))
                }
            }
            lines += ["نوع المصدر: مجلد", "عدد الملفات: \(files)", "عدد المجلدات: \(folders)", "إجمالي الحجم: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))", files == 0 ? "التحذير: المجلد لا يحتوي ملفات." : "النتيجة: يمكن نسخ المجلد."]
            return (files > 0, lines.joined(separator: "\n"))
        }

        let ext = url.pathExtension.lowercased()
        guard ext == "zip" || ext == "rar" else {
            return (false, (lines + ["نوع الملف: .\(ext.isEmpty ? "بدون امتداد" : ext)", "السبب: التطبيق يقبل ZIP وRAR فقط كأرشيفات."]).joined(separator: "\n"))
        }

        let signature = (try? FileHandle(forReadingFrom: url).read(upToCount: 8)) ?? nil ?? Data()
        let zipMagic = signature.starts(with: [0x50, 0x4B])
        let rarMagic = signature.starts(with: [0x52, 0x61, 0x72, 0x21])
        lines.append("الامتداد: \(ext.uppercased())")
        lines.append("توقيع الملف: \(zipMagic ? "ZIP" : rarMagic ? "RAR" : "غير معروف")")
        if (ext == "zip" && !zipMagic) || (ext == "rar" && !rarMagic) {
            lines.append("السبب المحتمل: امتداد الملف لا يطابق محتواه، أو الملف تالف/ليس أرشيفاً.")
            return (false, lines.joined(separator: "\n"))
        }

        do {
            let reader = try await ArchiveReader(reading: .fileURL(url))
            var count = 0
            var total: Int64 = 0
            var unsafe = 0
            var samples: [String] = []
            for try await item in reader {
                let path = item.entry.path.replacingOccurrences(of: "\\", with: "/")
                let parts = path.split(separator: "/", omittingEmptySubsequences: true)
                if path.hasPrefix("/") || parts.contains("..") || parts.contains(".") { unsafe += 1 }
                let data = Data(item.bytes)
                total += Int64(data.count)
                count += 1
                if samples.count < 5 { samples.append(path) }
                if count > 20_000 || total > 1_500_000_000 {
                    await reader.close()
                    lines.append("السبب: تجاوز الأرشيف الحد الآمن (20,000 ملف أو 1.5GB).")
                    return (false, lines.joined(separator: "\n"))
                }
            }
            await reader.close()
            lines += ["عدد العناصر: \(count)", "حجم البيانات المقروءة: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"]
            if !samples.isEmpty { lines.append("أمثلة:\n" + samples.joined(separator: "\n")) }
            if unsafe > 0 {
                lines.append("السبب: يحتوي الأرشيف على \(unsafe) مسار غير آمن وتم رفضه.")
                return (false, lines.joined(separator: "\n"))
            }
            guard count > 0 else {
                lines.append("السبب: الأرشيف فارغ أو لا يحتوي عناصر قابلة للقراءة.")
                return (false, lines.joined(separator: "\n"))
            }
            lines.append("النتيجة: اجتاز فحص القراءة والمسارات. لم يتم فك الملفات.")
            return (true, lines.joined(separator: "\n"))
        } catch {
            lines += ["النتيجة: فشل قراءة الأرشيف", "السبب التقني: \(error.localizedDescription)", "تلميح: قد يكون الملف RAR بإصدار غير مدعوم، أو ZIP تالفاً، أو الملف ناقص التحميل."]
            return (false, lines.joined(separator: "\n"))
        }
    }
}
