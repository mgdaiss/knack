import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.needsOnboarding {
                OnboardingView()
            } else {
                MainShell()
            }
        }
        .font(Theme.Fonts.body)
        .foregroundStyle(Theme.Colors.ink)
        .tint(Theme.Colors.indigo)
        .background(Theme.Colors.bg.ignoresSafeArea())
    }
}

struct MainShell: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Group {
                switch model.section {
                case .home: HomeView()
                case .discover: DiscoverView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.Colors.bg.ignoresSafeArea())
        }
        .task {
            await model.refreshAccount()
            await model.refreshUsage()
        }
    }
}
