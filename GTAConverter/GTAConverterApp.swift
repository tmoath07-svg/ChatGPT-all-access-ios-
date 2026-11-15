import SwiftUI

@main
struct GTAConverterApp: App {
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
