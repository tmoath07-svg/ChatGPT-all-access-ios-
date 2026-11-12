import SwiftUI
import UniformTypeIdentifiers

struct ModComparisonView: View {
    @State private var left: URL?
    @State private var right: URL?
    @State private var activePicker = 0
    @State private var showingPicker = false
    @State private var results: [INRPFComparedFile] = []
    @State private var errorText: String?
    @State private var isBusy = false

    private var counts: [(String, Int, Color)] {
        [("جديد", results.filter { $0.change == .added }.count, .green),
         ("محذوف", results.filter { $0.change == .removed }.count, .red),
         ("معدّل", results.filter { $0.change == .changed }.count, .orange),
         ("متطابق", results.filter { $0.change == .unchanged }.count, .secondary)]
    }

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("مقارنة نسختين من المود").font(.title2.bold()).foregroundStyle(.white)
                    folderButton("النسخة الأولى", folder: left) { activePicker = 1; showingPicker = true }
                    folderButton("النسخة الثانية", folder: right) { activePicker = 2; showingPicker = true }
                    Button(action: compare) {
                        Label(isBusy ? "جاري المقارنة..." : "قارن الملفات ببصمة SHA-256",
                              systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Color.purple).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.disabled(left == nil || right == nil || isBusy)
                    if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
                    if !results.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(counts, id: \.0) { item in
                                VStack {
                                    Text(String(item.1)).font(.title2.bold()).foregroundStyle(item.2)
                                    Text(item.0).font(.caption).foregroundStyle(.white.opacity(0.7))
                                }.frame(maxWidth: .infinity).padding(12)
                                    .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        ForEach(results, id: \.path) { item in
                            HStack(spacing: 8) {
                                Circle().fill(color(item.change)).frame(width: 8, height: 8)
                                Text(item.path).font(.caption.monospaced()).foregroundStyle(.white).lineLimit(2)
                                Spacer()
                                Text(label(item.change)).font(.caption2.bold()).foregroundStyle(color(item.change))
                            }.padding(10).background(.white.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }.padding(16)
            }
        }
        .navigationTitle("مقارنة المودات")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                if activePicker == 1 { left = url } else { right = url }
                results = []
                errorText = nil
            } catch { errorText = error.localizedDescription }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func folderButton(_ title: String, folder: URL?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption.bold()).foregroundStyle(.purple)
                Text(folder?.lastPathComponent ?? "اختر مجلد").font(.subheadline).foregroundStyle(.white)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
                .background(.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func compare() {
        guard let left, let right else { return }
        isBusy = true
        errorText = nil
        Task.detached(priority: .userInitiated) {
            let leftAccess = left.startAccessingSecurityScopedResource()
            let rightAccess = right.startAccessingSecurityScopedResource()
            defer {
                if leftAccess { left.stopAccessingSecurityScopedResource() }
                if rightAccess { right.stopAccessingSecurityScopedResource() }
            }
            return try INRPFFileComparison.compare(left: left, right: right)
        }.valueOnMain { result in
            switch result {
            case .success(let value): results = value
            case .failure(let error): errorText = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func label(_ value: INRPFComparedFile.Change) -> String {
        switch value { case .added: "جديد"; case .removed: "محذوف"; case .changed: "معدّل"; case .unchanged: "متطابق" }
    }
    private func color(_ value: INRPFComparedFile.Change) -> Color {
        switch value { case .added: .green; case .removed: .red; case .changed: .orange; case .unchanged: .secondary }
    }
}

struct HandlingAnalyzerView: View {
    @State private var showingPicker = false
    @State private var fields: [INRPFHandlingField] = []
    @State private var fileName = ""
    @State private var errorText: String?

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("محلل Handling.meta").font(.title2.bold()).foregroundStyle(.white)
                    Text("يعرض الحقول والقيم المقروءة من XML. لا يغيّر الملف الأصلي.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    Button { showingPicker = true } label: {
                        Label("اختيار handling.meta", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity).padding(14).background(.purple)
                            .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if !fileName.isEmpty { Text(fileName).font(.caption.monospaced()).foregroundStyle(.purple) }
                    if let errorText { Text(errorText).font(.caption).foregroundStyle(.red) }
                    ForEach(fields, id: \.name) { field in
                        HStack {
                            Text(field.name).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Text(field.value).font(.caption.monospaced().bold()).foregroundStyle(.white)
                        }.padding(11).background(.white.opacity(0.055)).clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }.padding(16)
            }
        }
        .navigationTitle("Handling Analyzer")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.xml, .item], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                fields = try INRPFHandlingParser.parse(data: Data(contentsOf: url))
                fileName = url.lastPathComponent
                errorText = nil
            } catch { errorText = error.localizedDescription }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

private extension Task where Success == Never, Failure == Never {
    static func unused() {}
}
