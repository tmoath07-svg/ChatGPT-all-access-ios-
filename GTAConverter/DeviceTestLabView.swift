import SwiftUI
import UIKit

struct INRPFDeviceTestLabView: View {
    @State private var report: INRPFDeviceTestReport?
    @State private var reportURL: URL?
    @State private var status = "شغّل الاختبار لإنشاء تقرير من هذا الجهاز."
    @State private var isRunning = false
    private let purple = Color(red: 0.57, green: 0.30, blue: 0.98)

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.025, blue: 0.065).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Label("مختبر جهاز INRPF", systemImage: "ipad.and.iphone").font(.title2.bold()).foregroundStyle(.white)
                    Text("اختبارات محلية للتخزين وقراءة الملفات وبيانات إصدار التطبيق، مع تقرير قابل للمشاركة.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    Button(action: runTests) {
                        HStack {
                            if isRunning { ProgressView().tint(.white) }
                            Label(isRunning ? "جاري الاختبار..." : "تشغيل اختبارات الجهاز", systemImage: "play.fill")
                        }.font(.headline).frame(maxWidth: .infinity).padding(15)
                            .background(purple).foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                    }.disabled(isRunning)
                    Text(status).font(.caption).foregroundStyle(.white.opacity(0.75))
                    if let report {
                        HStack {
                            metric("ناجح", value: "\(report.passedCount)", tint: .green)
                            metric("فاشل", value: "\(report.failedCount)", tint: report.failedCount == 0 ? .green : .red)
                        }
                        ForEach(report.results) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(item.passed ? .green : .red)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.subheadline.bold()).foregroundStyle(.white)
                                    Text(item.details).font(.caption).foregroundStyle(.white.opacity(0.65))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        if let reportURL {
                            ShareLink(item: reportURL) {
                                Label("مشاركة تقرير الاختبار", systemImage: "square.and.arrow.up")
                                    .font(.headline).frame(maxWidth: .infinity).padding(14)
                                    .background(.white.opacity(0.1)).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                            }
                        }
                    }
                    Text("لا يتحكم هذا المختبر بتطبيقات أخرى ولا يفتح اتصالاً عن بُعد. لا تُرسل التقارير تلقائياً؛ أنت تختار مشاركتها.")
                        .font(.caption2).foregroundStyle(.orange.opacity(0.9))
                }.padding(16)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationTitle("مختبر الجهاز").navigationBarTitleDisplayMode(.inline)
    }

    private func metric(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title.bold()).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.65))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.white.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func runTests() {
        isRunning = true
        defer { isRunning = false }
        do {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let info = Bundle.main.infoDictionary ?? [:]
            let result = INRPFDeviceTestCore.run(rootURL: docs,
                appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
                buildNumber: info["CFBundleVersion"] as? String ?? "unknown",
                platform: "iOS \(UIDevice.current.systemVersion)", deviceModel: UIDevice.current.model)
            let folder = docs.appendingPathComponent("INRPF-Test-Reports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("INRPF-Test-\(Int(Date().timeIntervalSince1970)).txt")
            try Data(result.text.utf8).write(to: url, options: .atomic)
            report = result
            reportURL = url
            status = result.allPassed ? "نجحت جميع الاختبارات المحلية." : "فشلت بعض الاختبارات. راجع التفاصيل."
        } catch { status = "تعذر تشغيل الاختبار أو حفظ التقرير: \(error.localizedDescription)" }
    }
}
