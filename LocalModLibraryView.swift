import SwiftUI

struct LocalModLibraryView: View {
    let featureID: Int

    @State private var items: [URL] = []
    @State private var reportText = ""
    @State private var selectedCategory = "الكل"

    private var title: String { featureID == 10 ? "معرض موداتك" : "مكتبة المودات المحلية" }

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(.title2.bold()).foregroundStyle(.white)
                    Text("العناصر هنا محفوظة داخل مساحة INRPF على الجهاز. لا توجد مزامنة أو رفع سحابي.")
                        .font(.caption).foregroundStyle(.white.opacity(0.62))
                    Picker("المصدر", selection: $selectedCategory) {
                        Text("الكل").tag("الكل")
                        Text("Imports").tag("Imports")
                        Text("FiveM").tag("FiveM")
                    }
                    .pickerStyle(.segmented)
                    Button("تحديث المكتبة") { reload() }
                        .frame(maxWidth: .infinity).padding(10)
                        .background(.purple).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    if items.isEmpty {
                        Text("ما فيه مودات مستوردة في هذا التصنيف حتى الآن.")
                            .font(.caption).foregroundStyle(.white.opacity(0.6)).padding(20)
                    }
                    ForEach(items, id: \.path) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "shippingbox.fill").foregroundStyle(.purple)
                                Text(item.lastPathComponent).font(.caption.monospaced().bold()).foregroundStyle(.white)
                                Spacer()
                            }
                            HStack(spacing: 8) {
                                Button("تحليل") { analyze(item) }
                                    .font(.caption.bold()).padding(9)
                                    .background(.purple.opacity(0.22)).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                ShareLink(item: item) {
                                    Label("مشاركة", systemImage: "square.and.arrow.up")
                                        .font(.caption.bold()).padding(9)
                                        .background(.white.opacity(0.08)).foregroundStyle(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(12).background(.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !reportText.isEmpty {
                        Text(reportText).font(.caption.monospaced()).foregroundStyle(.white)
                            .textSelection(.enabled).padding(12)
                            .background(.black.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }.padding(16)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: selectedCategory) { _ in reload() }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func reload() {
        do {
            let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let root = documents.appendingPathComponent("GTA Converter", isDirectory: true)
            let categories = selectedCategory == "الكل" ? ["Imports", "FiveM"] : [selectedCategory]
            items = categories.flatMap { category -> [URL] in
                let folder = root.appendingPathComponent(category, isDirectory: true)
                return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            }.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            reportText = ""
        } catch {
            reportText = "تعذر قراءة المكتبة: \(error.localizedDescription)"
        }
    }

    private func analyze(_ item: URL) {
        do {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                reportText = "العنصر ملف مفرد. استورده كمجلد إذا تبي تحلل بنية مود كاملة."
                return
            }
            let report = try ModAnalyzer.analyze(at: item)
            reportText = report.reportText
            INRPFLocalTimeline.record("تحليل من المكتبة", details: item.lastPathComponent)
        } catch {
            reportText = "تعذر تحليل العنصر: \(error.localizedDescription)"
        }
    }
}
