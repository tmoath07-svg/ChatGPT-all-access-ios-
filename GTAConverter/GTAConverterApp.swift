import SwiftUI

@main
struct GTAConverterApp: App {
    var body: some Scene {
        WindowGroup {
            // GitHub is now the permanent INRPF workspace. Authentication,
            // repository management, uploads and Actions live in one place.
            GitHubIntegrationView()
                .preferredColorScheme(.dark)
        }
    }
}
