import SwiftUI
import Foundation

struct INRPFHistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let title: String
    let details: String
}

enum INRPFLocalTimeline {
    private static let storageKey = "inrpf.local.timeline.v1"

    static func record(_ title: String, details: String) {
        var entries = load()
        entries.insert(INRPFHistoryEntry(id: UUID(), date: Date(), title: String(title.prefix(100)), details: String(details.prefix(500))), at: 0)
        entries = Array(entries.prefix(250))
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func load() -> [INRPFHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([INRPFHistoryEntry].self, from: data) else { return [] }
        return entries
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

struct LocalTimelineView: View {
    @State private var entries: [INRPFHistoryEntry] = []

    var body: some View {
        ZStack {
            GTAAppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("سجل INRPF المحلي").font(.title2.bold()).foregroundStyle(.white)
                    Text("يسجل العمليات التي نفذتها الأدوات المرتبطة بالسجل على هذا الجهاز فقط.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    Button("تحديث") { entries = INRPFLocalTimeline.load() }
                        .frame(maxWidth: .infinity).padding(10).background(.purple)
                        .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                    Button("مسح السجل") {
                        INRPFLocalTimeline.clear()
                        entries = []
                    }
                    .font(.caption).foregroundStyle(.red)
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.title).font(.subheadline.bold()).foregroundStyle(.white)
                            Text(entry.details).font(.caption).foregroundStyle(.white.opacity(0.65))
                            Text(entry.date, style: .date).font(.caption2).foregroundStyle(.purple)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if entries.isEmpty {
                        Text("ما تم تسجيل عمليات بعد.").font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }.padding(16)
            }
        }
        .navigationTitle("Mod Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entries = INRPFLocalTimeline.load() }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
