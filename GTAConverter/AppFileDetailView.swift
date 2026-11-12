import SwiftUI

struct AppFileDetailView: View {
    let url: URL
    @State private var fileSize = ""

    private var fileExtension: String {
        url.pathExtension.isEmpty ? "FILE" : url.pathExtension.uppercased()
    }

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 12) {
                        Image(systemName: iconName)
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(.purple)
                        Text(url.lastPathComponent)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                        Text(fileExtension + " • " + (fileSize.isEmpty ? "جارٍ قراءة الحجم" : fileSize))
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                    NavigationLink {
                        if ["zip", "rar"].contains(url.pathExtension.lowercased()) {
                            ContentView(initialSourceURL: url)
                        } else {
                            LocalEngineView(initialFile: url)
                        }
                    } label: {
                        Label(
                            ["zip", "rar"].contains(url.pathExtension.lowercased())
                                ? "إرسال إلى تجهيز المود"
                                : "فتح الملف في المحرك المحلي",
                            systemImage: ["zip", "rar"].contains(url.pathExtension.lowercased())
                                ? "shippingbox.fill" : "cpu.fill"
                        )
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(15)
                        .background(Color.purple.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: url) {
                        Label("مشاركة أو فتح باستخدام تطبيق آخر", systemImage: "square.and.arrow.up")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(.white.opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .foregroundStyle(.white)
                    }

                    Text("هذا الملف محفوظ داخل مساحة INRPF. اختر المحرك المحلي لتشغيل الفحص أو التحويل الذي يدعمه امتداد الملف.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(13)
                        .background(.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
        }
        .navigationTitle("تفاصيل الملف")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values?.fileSize {
                fileSize = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
        }
    }

    private var iconName: String {
        switch url.pathExtension.lowercased() {
        case "rpf": return "archivebox.fill"
        case "zip", "rar", "7z": return "doc.zipper"
        case "yft", "ydr", "ydd", "ytd": return "shippingbox.fill"
        case "xml", "meta", "txt": return "doc.text.fill"
        case "png", "jpg", "jpeg", "dds": return "photo.fill"
        default: return "doc.fill"
        }
    }
}
