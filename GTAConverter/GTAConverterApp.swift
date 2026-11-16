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

    private var resolvedHorizontalSizeClass: UserInterfaceSizeClass {
        switch interfaceMode {
        case "ios": return .compact
        case "ipados": return .regular
        default: return UIDevice.current.userInterfaceIdiom == .pad ? .regular : .compact
        }
    }

    var body: some Scene {
        WindowGroup {
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
            .preferredColorScheme(.dark)
            .onOpenURL { _ in
                selectedTab = 1
            }
            .environment(\.horizontalSizeClass, resolvedHorizontalSizeClass)
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
                    Label("واجهة مضغوطة مناسبة للآيفون.", systemImage: "iphone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if interfaceMode == "ipados" {
                    Label("واجهة واسعة تستفيد من مساحة شاشة الآيباد.", systemImage: "ipad")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("يختار INRPF التخطيط تلقائياً حسب نوع الجهاز.", systemImage: "arrow.left.arrow.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("يتغير نمط العرض داخل INRPF فقط، ولا يغيّر نظام الجهاز أو طريقة عمل الأدوات.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("نمط الواجهة")
        .navigationBarTitleDisplayMode(.inline)
    }
}
