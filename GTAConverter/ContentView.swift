import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var showingImporter = false
    @State private var selectedFileName = "ما تم اختيار ملف"
    @State private var packNames = ""
    @State private var generatedURL: URL?
    @State private var status = "اختر ملف ZIP أو مجلد مودات، ثم أضف أسماء الحزم."
    @State private var isError = false

    private let purple = Color(red: 0.55, green: 0.28, blue: 0.95)

    private var names: [String] {
        packNames
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.045, green: 0.035, blue: 0.075).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        fileCard
                        packCard
                        generateButton
                        if let generatedURL {
                            ShareLink(item: generatedURL) {
                                Label("مشاركة ملف dlclist.xml", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.white.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .tint(.white)
                        }
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(isError ? .red : .white.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.zip, .folder],
                allowsMultipleSelection: false,
                onCompletion: handleImport
            )
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(purple)
                Spacer()
                Text("BETA")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(purple.opacity(0.22))
                    .clipShape(Capsule())
            }
            Text("GTA CONVERTER")
                .font(.system(size: 29, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("تجهيز مودات قراند للـ PS4")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
            Text("استيراد الملفات وإنشاء dlclist.xml")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
            Text("الإصدار 1.0.0 • ملف البناء يحتاج توقيعاً قبل التثبيت")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(colors: [purple.opacity(0.32), Color.white.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("ملفات المود", systemImage: "archivebox.fill")
                .font(.headline)
                .foregroundStyle(.white)
            Text(selectedFileName)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2)
            Button {
                showingImporter = true
            } label: {
                Label("اختيار ZIP أو مجلد", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(purple)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var packCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("أسماء الحزم", systemImage: "list.bullet.rectangle")
                .font(.headline)
                .foregroundStyle(.white)
            Text("اكتب اسم كل مجلد DLC في سطر مستقل، مثل rb3nasb")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
            TextEditor(text: $packNames)
                .frame(minHeight: 145)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(18)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var generateButton: some View {
        Button(action: generateXML) {
            Label("إنشاء dlclist.xml", systemImage: "doc.badge.gearshape")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(purple)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(names.isEmpty)
        .opacity(names.isEmpty ? 0.45 : 1)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let source = try result.get().first else { return }
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            selectedFileName = source.lastPathComponent
            status = "تم استيراد الملف. أضف أسماء الحزم لإنشاء ملف القائمة."
            isError = false
        } catch {
            status = "تعذر استيراد الملف: \(error.localizedDescription)"
            isError = true
        }
    }

    private func generateXML() {
        let entries = names.map { name in
            "        <Item>/data/orbx/gta/rpf/dlc_addon/\(xmlEscape(name))/</Item>"
        }.joined(separator: "\n")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <SMandatoryPacksData>
          <Paths>
        \(entries)
          </Paths>
        </SMandatoryPacksData>
        """
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dlclist.xml")
            try xml.write(to: url, atomically: true, encoding: .utf8)
            generatedURL = url
            status = "تم إنشاء dlclist.xml بعدد \(names.count) حزمة."
            isError = false
        } catch {
            status = "فشل إنشاء الملف: \(error.localizedDescription)"
            isError = true
        }
    }

    private func xmlEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
