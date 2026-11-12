import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct DLClistEditorView: View {
    @State private var showingPicker = false
    @State private var xmlText = """
    <?xml version="1.0" encoding="UTF-8"?>
    <SMandatoryPacksData>
      <Paths>
      </Paths>
    </SMandatoryPacksData>
    """
    @State private var status = "افتح dlclist.xml أو الصق محتواه. يتم حفظ نسخة جديدة ولا يتم استبدال الأصل."
    @State private var shareURL: URL?

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("محرر dlclist.xml").font(.title2.bold()).foregroundStyle(.white)
                    Text("تحرير محلي مع التحقق من XML قبل حفظ نسخة منفصلة.")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                    Button { showingPicker = true } label: {
                        Label("فتح ملف XML", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity).padding(12).background(.purple)
                            .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    TextEditor(text: $xmlText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 360)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Button(action: saveValidatedCopy) {
                        Label("تحقق واحفظ نسخة XML", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity).padding(13).background(.purple)
                            .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text(status).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    if let shareURL {
                        ShareLink(item: shareURL) {
                            Label("مشاركة نسخة dlclist.xml", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity).padding(12)
                                .background(.white.opacity(0.08)).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }.padding(16)
            }
        }
        .navigationTitle("XML Studio")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                guard size <= 2 * 1024 * 1024 else {
                    status = "الحد الأقصى لملف XML هو 2MB."
                    return
                }
                xmlText = try String(contentsOf: url, encoding: .utf8)
                status = "تم فتح \(url.lastPathComponent). الأصل لم يتغير."
                shareURL = nil
            } catch {
                status = "تعذر فتح XML: \(error.localizedDescription)"
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func saveValidatedCopy() {
        let parser = XMLParser(data: Data(xmlText.utf8))
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            status = "XML غير صالح: \(parser.parserError?.localizedDescription ?? "خطأ غير معروف")"
            shareURL = nil
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("dlclist-validated-\(UUID().uuidString).xml")
            try Data(xmlText.utf8).write(to: url, options: .atomic)
            shareURL = url
            status = "XML صالح. تم حفظ نسخة منفصلة، والملف الأصلي لم يتغير."
        } catch {
            status = "تعذر حفظ النسخة: \(error.localizedDescription)"
        }
    }
}
