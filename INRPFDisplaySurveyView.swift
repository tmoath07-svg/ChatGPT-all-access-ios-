import SwiftUI
import UIKit

struct INRPFDisplaySurveyView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.displayScale) private var displayScale
    @AppStorage("inrpf_interface_mode") private var interfaceMode = "auto"
    @State private var issue = "square"
    @State private var frequency = "always"
    @State private var notes = ""
    @State private var sending = false
    @State private var status = ""
    @State private var sent = false

    private let endpoint = URL(string: "https://inrpf-server.onrender.com/api/display-surveys")!
    private let purple = Color(red: 0.57, green: 0.30, blue: 0.98)

    private var deviceFamily: String {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return "iPhone"
        case .pad: return "iPad"
        default: return "other"
        }
    }

    private func orientation(for size: CGSize) -> String {
        guard size.width > 0, size.height > 0 else { return "unknown" }
        return size.width >= size.height ? "landscape" : "portrait"
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size

            ZStack {
                Color(red: 0.035, green: 0.025, blue: 0.065).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("استبيان مشكلة الشاشة", systemImage: "rectangle.inset.filled.and.person.filled")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("جاوب عن المشكلة اللي تظهر لك. بنرسل الإجابات مع معلومات مساحة التطبيق التقنية فقط لمساعدتنا نحدد سببها.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.72))

                        group("وش المشكلة اللي تشوفها؟") {
                            option("الشاشة تطلع مربعة أو داخل إطار صغير", value: "square", selection: $issue)
                            option("الواجهة مقصوصة من الأطراف", value: "cropped", selection: $issue)
                            option("العناصر أو الخطوط أكبر من اللازم", value: "oversized", selection: $issue)
                            option("العناصر صغيرة أو متباعدة", value: "tiny", selection: $issue)
                            option("تتغير المشكلة عند تبديل iOS وiPadOS", value: "layout_switch", selection: $issue)
                            option("مشكلة ثانية", value: "other", selection: $issue)
                        }
                        group("متى تظهر المشكلة؟") {
                            option("كل مرة أفتح التطبيق", value: "always", selection: $frequency)
                            option("أحياناً فقط", value: "sometimes", selection: $frequency)
                            option("بعد تدوير الجهاز", value: "after_rotation", selection: $frequency)
                            option("بعد تغيير نمط الواجهة", value: "after_switch", selection: $frequency)
                            option("ظهرت مرة واحدة", value: "once", selection: $frequency)
                        }
                        group("ملاحظات إضافية (اختياري)") {
                            TextField("اكتب ملاحظة مختصرة", text: $notes, axis: .vertical)
                                .lineLimit(2...4).padding(12)
                                .background(.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                        }
                        group("معلومات مساحة التطبيق") {
                            detail("الجهاز", deviceFamily + " • " + UIDevice.current.model)
                            detail("النظام", UIDevice.current.systemVersion)
                            detail("مساحة التطبيق", "\(Int(viewportSize.width)) × \(Int(viewportSize.height))")
                            detail("مقياس العرض", "\(displayScale)x")
                            detail("اتجاه مساحة التطبيق", orientation(for: viewportSize))
                            detail("Horizontal / Vertical", "\(horizontalSizeClass == .compact ? "compact" : "regular") / \(verticalSizeClass == .compact ? "compact" : "regular")")
                            detail("نمط INRPF", interfaceMode)
                            detail("إصدار التطبيق", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
                            detail("رقم البناء", Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")
                        }
                        Button {
                            Task { await submit(viewportSize: viewportSize) }
                        } label: {
                            HStack {
                                if sending { ProgressView().tint(.white) }
                                Text(sending ? "جاري الإرسال..." : sent ? "تم إرسال الإجابة" : "إرسال الاستبيان")
                            }
                            .font(.headline.bold()).frame(maxWidth: .infinity).padding(15)
                            .background(purple).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        }
                        .disabled(sending || sent)
                        if !status.isEmpty {
                            Text(status).font(.footnote).foregroundStyle(sent ? .green : .orange)
                        }
                        Text("الاستبيان اختياري ولا يجمع الاسم أو البريد أو الصور أو الموقع.")
                            .font(.caption2).foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(18).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("تشخيص الشاشة")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundStyle(.white)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

    private func option(_ title: String, value: String, selection: Binding<String>) -> some View {
        Button { selection.wrappedValue = value } label: {
            HStack {
                Image(systemName: selection.wrappedValue == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(purple)
                Text(title).foregroundStyle(.white).font(.subheadline)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Text(value).foregroundStyle(.white).multilineTextAlignment(.trailing)
        }.font(.caption)
    }

    @MainActor
    private func submit(viewportSize: CGSize) async {
        sending = true
        defer { sending = false }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let payload: [String: String] = [
            "issue": issue, "frequency": frequency,
            "interface_mode": interfaceMode, "device_family": deviceFamily,
            "device_model": UIDevice.current.model,
            "os_version": UIDevice.current.systemVersion,
            "screen_size": "\(Int(viewportSize.width))x\(Int(viewportSize.height))",
            "screen_scale": "\(displayScale)",
            "measurement_scope": "scene_viewport",
            "orientation": orientation(for: viewportSize),
            "horizontal_size_class": horizontalSizeClass == .compact ? "compact" : "regular",
            "vertical_size_class": verticalSizeClass == .compact ? "compact" : "regular",
            "app_version": version, "build_number": build,
            "notes": String(notes.prefix(300))
        ]
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
                let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "تعذر قبول الاستبيان"
                throw NSError(domain: "INRPFDisplaySurvey", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
            }
            sent = true
            status = "وصلت إجابتك بنجاح. شكراً لمساعدتنا في تحديد المشكلة."
        } catch {
            status = "ما قدرنا نرسل الإجابة: \(error.localizedDescription). حاول مرة ثانية."
        }
    }
}
