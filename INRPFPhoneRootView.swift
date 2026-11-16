import SwiftUI

/// Dedicated compact-width shell for iPhone-sized scenes.
/// Feature views and service models remain shared with the iPad experience.
struct INRPFPhoneRootView: View {
    @State private var selectedTab = 0

    private let tabs: [(title: String, symbol: String)] = [
        ("GitHub", "chevron.left.forwardslash.chevron.right"),
        ("الأدوات", "square.grid.2x2.fill"),
        ("Gemini", "sparkles"),
        ("AI Agent", "brain.head.profile")
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { GitHubIntegrationView() }
                .tabItem { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(0)

            ContentView()
                .tabItem { Label("الأدوات", systemImage: "square.grid.2x2.fill") }
                .tag(1)

            GeminiToolView()
                .tabItem { Label("Gemini", systemImage: "sparkles") }
                .tag(2)

            NavigationStack { AutonomousAgentView() }
                .tabItem { Label("AI Agent", systemImage: "brain.head.profile") }
                .tag(3)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            phoneTabBar
        }
        .onOpenURL { _ in
            selectedTab = 1
        }
        .preferredColorScheme(.dark)
        .tint(.purple)
    }

    private var phoneTabBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    guard selectedTab != index else { return }
                    selectedTab = index
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: selectedTab == index ? .semibold : .regular))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selectedTab == index ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selectedTab == index ? Color.white : Color.white.opacity(0.58))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if selectedTab == index {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(Color.purple.opacity(0.28))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.09)).frame(height: 0.5)
        }
    }
}
