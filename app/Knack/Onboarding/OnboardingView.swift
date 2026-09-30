import AuthenticationServices
import KeyboardShortcuts
import KnackCore
import SwiftUI

/// Sign in with Apple → starter credit → Accessibility walkthrough → hotkey setup (SPEC §2).
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: Step = .signIn

    enum Step { case signIn, credit, accessibility, hotkeys }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            HStack(spacing: 14) {
                ForEach(["say-it-better", "explain-this", "fridge-chef", "bedtime-stories", "the-decider"], id: \.self) { asset in
                    Image(asset)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                        .themeShadow(Theme.Shadows.tile)
                        .accessibilityHidden(true)
                }
            }
            Group {
                switch step {
                case .signIn: SignInStep { step = .credit }
                case .credit: CreditStep { step = AccessibilityPermission.isGranted ? .hotkeys : .accessibility }
                case .accessibility: AccessibilityStep { step = .hotkeys }
                case .hotkeys: HotkeysStep { model.onboardingComplete = true }
                }
            }
            .frame(maxWidth: 560)
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.bg.ignoresSafeArea())
        .onAppear { if model.isSignedIn { step = .credit } }
    }
}

private struct SignInStep: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    @State private var error: KnackError?
    @State private var working = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Meet your helpers").font(Theme.Fonts.greeting)
            Text("Little characters that each do one job well, right on your Mac.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.muted)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                    run { try await model.signInWithApple(credential) }
                case .failure(let err):
                    if (err as? ASAuthorizationError)?.code != .canceled { error = .unauthorized }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(width: 260, height: 44)
            .clipShape(Capsule())
            .disabled(working)

            if AppConfig.allowsDevSignIn {
                Button("Use a test account") { run { try await model.devSignIn() } }
                    .buttonStyle(SoftPillButtonStyle())
                    .disabled(working)
            }
            if let error {
                Text(error.friendlyMessage).font(Theme.Fonts.bodyBold).foregroundStyle(Theme.Colors.muted)
            }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await action()
                next()
            } catch let e as KnackError {
                error = e
            } catch {
                self.error = .server
            }
        }
    }
}

private struct CreditStep: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(model.givenName.map { "You're in, \($0)!" } ?? "You're in!").font(Theme.Fonts.greeting)
            if let balance = model.account?.balanceUSD {
                Text("Knack's on us: \(Money.format(balance)) of credit so your helpers can get to work. No card needed.")
                    .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.muted).multilineTextAlignment(.center)
            } else {
                ProgressView().controlSize(.small)
            }
            Button("Next", action: next).buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction)
        }
        .task { await model.refreshAccount() }
    }
}

private struct AccessibilityStep: View {
    let next: () -> Void
    @State private var granted = AccessibilityPermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Let your helpers see your selection").font(Theme.Fonts.greeting)
            Text("Say It Better and Explain This work on text you select in any app. macOS asks you to allow that once, under Accessibility.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.muted)
            VStack(alignment: .leading, spacing: 8) {
                Label("Click **Open System Settings** below.", systemImage: "1.circle.fill")
                Label("Go to **Privacy & Security ▸ Accessibility**.", systemImage: "2.circle.fill")
                Label("Turn on the switch next to **Knack**.", systemImage: "3.circle.fill")
            }
            .font(Theme.Fonts.body)
            .card()
            Text("Helpers only read your selection when you press their shortcut, and only the selected text is sent to the AI.")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.muted)
            HStack {
                if granted {
                    Label("Allowed. Thank you!", systemImage: "checkmark.circle.fill").font(Theme.Fonts.bodyBold)
                    Spacer()
                    Button("Next", action: next).buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction)
                } else {
                    Button("Open System Settings") {
                        AccessibilityPermission.requestPrompt()
                        AccessibilityPermission.openSystemSettings()
                    }
                    .buttonStyle(PillButtonStyle())
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Waiting for the switch…").font(Theme.Fonts.caption) }
                    Spacer()
                    Button("Later", action: next).buttonStyle(SoftPillButtonStyle())
                }
            }
        }
        .task {
            await AccessibilityPermission.waitUntilGranted()
            granted = AccessibilityPermission.isGranted
        }
    }
}

private struct HotkeysStep: View {
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your shortcuts").font(Theme.Fonts.greeting)
            Text("Select text anywhere and press a shortcut. Change them now or later in Settings.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.muted)
            VStack(spacing: 12) {
                HotkeyRow(title: "Say It Better", asset: "say-it-better", name: .sayItBetter)
                HotkeyRow(title: "Explain This", asset: "explain-this", name: .explainThis)
            }
            .card()
            HStack {
                Spacer()
                Button("Start using Knack", action: next).buttonStyle(PillButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct HotkeyRow: View {
    let title: String
    let asset: String
    let name: KeyboardShortcuts.Name

    var body: some View {
        HStack(spacing: 12) {
            Image(asset).resizable().frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous))
                .accessibilityHidden(true)
            Text(title).font(Theme.Fonts.bodyBold)
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
        }
    }
}
