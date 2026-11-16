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

    var body: some Scene {
        WindowGroup {
            GeometryReader { viewport in
                INRPFPhoneRootView()
                    .frame(
                        width: max(1, viewport.size.width),
                        height: max(1, viewport.size.height),
                        alignment: .topLeading
                    )
                    .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .preferredColorScheme(.dark)
        }
    }
}
