import AuthenticationServices
import KnackCore
import SwiftUI

/// Sign in → starter credit. The Accessibility walkthrough and hotkey setup join in M2.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var error: KnackError?
    @State private var working = false

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
            if model.isSignedIn {
                welcome
            } else {
                signIn
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.bg.ignoresSafeArea())
    }

    private var signIn: some View {
        VStack(spacing: 16) {
            Text("Meet your helpers")
                .font(Theme.Fonts.greeting)
            Text("Little characters that each do one job well, right on your Mac.")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.muted)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(width: 260, height: 44)
            .clipShape(Capsule())
            .disabled(working)

            if AppConfig.allowsDevSignIn {
                Button("Use a test account") {
                    run { try await model.devSignIn() }
                }
                .buttonStyle(SoftPillButtonStyle())
                .disabled(working)
            }
            if let error {
                Text(error.friendlyMessage)
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.muted)
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Text(model.givenName.map { "You're in, \($0)!" } ?? "You're in!")
                .font(Theme.Fonts.greeting)
            if let balance = model.account?.balanceUSD {
                Text("Knack's on us: \(Money.format(balance)) of credit so your helpers can get to work. No card needed.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView().controlSize(.small)
            }
            Button("Let's go") { model.onboardingComplete = true }
                .buttonStyle(PillButtonStyle())
        }
        .task { await model.refreshAccount() }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            run { try await model.signInWithApple(credential) }
        case .failure(let err):
            if (err as? ASAuthorizationError)?.code == .canceled { return }
            error = .unauthorized
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        working = true
        error = nil
        Task {
            defer { working = false }
            do {
                try await action()
            } catch let e as KnackError {
                error = e
            } catch {
                self.error = .server
            }
        }
    }
}
