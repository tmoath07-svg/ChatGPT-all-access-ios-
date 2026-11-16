import SwiftUI
import UIKit
import UserNotifications

final class INRPFAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        INRPFBackgroundTransferManager.shared.handleEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
}

@main
struct GTAConverterApp: App {
    @UIApplicationDelegateAdaptor(INRPFAppDelegate.self) private var appDelegate
    @State private var selectedTab = 0
    @AppStorage("inrpf_interface_mode") private var interfaceMode = "auto"

    // The preference changes the content width only. SwiftUI keeps the real
    // scene size classes and traits supplied by the current window.
    private var appTabs: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let tabWidth = interfaceMode == "ios" ? min(560, availableWidth) : availableWidth

            ZStack {
                Color.black.ignoresSafeArea()
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        GitHubIntegrationView()
                    }
                    .tabItem {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .tag(0)

                    NavigationStack {
                        GeminiToolView()
                    }
                    .tabItem {
                        Label("Gemini", systemImage: "sparkles")
                    }
                    .tag(2)

                    ContentView()
                        .tabItem {
                            Label("الأدوات", systemImage: "square.grid.2x2.fill")
                        }
                        .tag(1)

                    NavigationStack {
                        AutonomousAgentView()
                    }
                    .tabItem {
                        Label("AI Agent", systemImage: "brain.head.profile")
                    }
                    .tag(3)
                }
                .frame(maxWidth: tabWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onOpenURL { _ in
            selectedTab = 1
        }
    }

    var body: some Scene {
        WindowGroup {
            GeometryReader { scene in
                if UIDevice.current.userInterfaceIdiom == .phone || scene.size.width < 600 {
                    INRPFPhoneRootView()
                } else {
                    appTabs
                        .preferredColorScheme(.dark)
                }
            }
        }
    }
}

struct InterfaceModeSettingsView: View {
    @AppStorage("inrpf_interface_mode") private var interfaceMode = "auto"

    var body: some View {
        Form {
            Section("نمط الواجهة") {
                Picker("طريقة العرض", selection: $interfaceMode) {
                    Text("تلقائي").tag("auto")
                    Text("iOS").tag("ios")
                    Text("iPadOS").tag("ipados")
                }
                .pickerStyle(.segmented)

                if interfaceMode == "ios" {
                    Label("تخطيط مضغوط بعرض أقصى 560 نقطة، ويتكيف مع مساحة النافذة.", systemImage: "iphone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if interfaceMode == "ipados" {
                    Label("تخطيط واسع يستفيد من مساحة النافذة المتاحة.", systemImage: "ipad")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("يضبط INRPF عرض المحتوى تلقائياً، مع احترام حجم النافذة الفعلي.", systemImage: "arrow.left.arrow.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("هذا الخيار يغيّر عرض محتوى INRPF فقط. لا يغيّر قياسات النظام أو فئات الحجم التي يحددها iOS أو iPadOS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("نمط الواجهة")
        .navigationBarTitleDisplayMode(.inline)
    }
}
