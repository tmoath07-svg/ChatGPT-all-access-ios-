import SwiftUI

@main
struct GTAConverterApp: App {
    var body: some Scene {
        WindowGroup {
            INRPFRootView()
                .preferredColorScheme(.dark)
        }
    }
}

/// GitHub is the app's entry point. The existing INRPF workspace is shown
/// only after the GitHub device-flow session has been validated.
private struct INRPFRootView: View {
    @AppStorage("gta_github_authenticated") private var isGitHubAuthenticated = false

    var body: some View {
        Group {
            if isGitHubAuthenticated {
                ContentView()
            } else {
                NavigationStack {
                    GitHubIntegrationView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isGitHubAuthenticated)
        .onAppear { isGitHubAuthenticated = false }
    }
}