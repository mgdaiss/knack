import KnackCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image("knack-logo")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous))
                    .accessibilityHidden(true)
                Text("knack")
                    .font(Theme.Fonts.logo)
                    .kerning(-0.5)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Knack")

            NavItem(title: "Home", systemImage: "house", section: .home)
            NavItem(title: "Discover", systemImage: "safari", section: .discover)
            NavItem(title: "Settings", systemImage: "slider.horizontal.3", section: .settings)

            Spacer(minLength: 16)

            CreditCard()
        }
        .padding(.top, 44 + 16) // clears the traffic lights in the hidden title bar
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
        .frame(width: Theme.Size.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.sidebar.ignoresSafeArea())
    }
}

private struct NavItem: View {
    @Environment(AppModel.self) private var model
    let title: String
    let systemImage: String
    let section: AppModel.Section

    var body: some View {
        let selected = model.section == section
        Button {
            model.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 18)
                Text(title).font(Theme.Fonts.nav)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background {
                if selected {
                    Capsule().fill(Theme.Colors.surface).themeShadow(Theme.Shadows.navSelected)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Bottom-of-sidebar credit summary. Credit is on us for now, so there's no top-up.
private struct CreditCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credit on us")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.muted)
            Text(model.account.map { Money.format($0.balanceUSD) } ?? "—")
                .font(Theme.Fonts.bigNumber)
            if let account = model.account {
                Text("Used this month: \(Money.format(account.month.spentUSD))")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.sidebarCard, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

enum Money {
    /// Dollars, with extra precision for sub-cent amounts so tiny AI costs don't read as $0.00.
    static func format(_ usd: Double) -> String {
        let style = FloatingPointFormatStyle<Double>.Currency(code: "USD")
        if usd > 0 && usd < 0.01 {
            return usd.formatted(style.precision(.fractionLength(4)))
        }
        return usd.formatted(style.precision(.fractionLength(2)))
    }
}
