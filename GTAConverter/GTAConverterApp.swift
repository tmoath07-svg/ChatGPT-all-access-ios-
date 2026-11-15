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
}

@main
struct GTAConverterApp: App {
    @UIApplicationDelegateAdaptor(INRPFAppDelegate.self) private var appDelegate
    @State private var selectedTab = 0

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

                ContentView()
                    .tabItem {
                        Label("الأدوات", systemImage: "square.grid.2x2.fill")
                    }
                    .tag(1)
            }
            .preferredColorScheme(.dark)
            // Route Files > Open In > INRPF into the legacy importer tab.
            .onOpenURL { _ in
                selectedTab = 1
            }
        }
    }
}
