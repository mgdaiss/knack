import AppKit
import AuthenticationServices
import KnackCore
import Observation
import SwiftUI

/// App-wide state: account, skills, model routing and navigation.
@MainActor
@Observable
final class AppModel {
    enum Section: Hashable {
        case home, discover, settings
    }

    var section: Section = .home

    let registry: SkillRegistry
    let cloud: KnackCloudClient
    let usage: UsageLog
    let styleSamples: StyleSampleStore
    let catalog: Catalog
    @ObservationIgnored private(set) var skillHost: SkillHost!
    private(set) var router: ModelRouter

    /// Set by the UI so non-view code (hotkeys, ⌘K, menu bar, URLs) can open windows.
    @ObservationIgnored var openWindowAction: ((String) -> Void)?
    @ObservationIgnored var openHomeAction: (() -> Void)?

    @ObservationIgnored private let selection = SystemSelectionService()
    @ObservationIgnored private let imageInput = AppImageInput()
    @ObservationIgnored private let notifications = AppNotifications()

    /// Skill detail sheet shown from Discover.
    var detailSkillID: String?

    private(set) var isSignedIn: Bool
    private(set) var account: Account?
    private(set) var accountError: KnackError?
    /// Successful runs per skill over the last 7 days, from the local usage log.
    private(set) var weekCounts: [String: Int] = [:]

    /// Onboarding is finished once the user has signed in and seen the welcome steps.
    var onboardingComplete: Bool {
        didSet { UserDefaults.standard.set(onboardingComplete, forKey: Keys.onboardingComplete) }
    }

    /// Given name from Sign in with Apple (only sent the first time). Kept on this Mac only.
    var givenName: String? {
        didSet { UserDefaults.standard.set(givenName, forKey: Keys.givenName) }
    }

    #if DEBUG
    /// DEBUG only: route model calls straight to OpenRouter with the developer's own key.
    var useDirectProvider: Bool {
        didSet {
            UserDefaults.standard.set(useDirectProvider, forKey: Keys.useDirectProvider)
            router = Self.makeRouter(cloud: cloud, usage: usage, direct: useDirectProvider)
        }
    }
    #endif

    private enum Keys {
        static let onboardingComplete = "onboarding.complete"
        static let givenName = "profile.givenName"
        static let useDirectProvider = "debug.useDirectProvider"
        static let devDeviceID = "debug.deviceID"
    }

    init() {
        let defaults = UserDefaults.standard
        registry = SkillRegistry(store: UserDefaultsInstallStateStore())
        registry.load(from: AppConfig.bundledSkillsDirectory)
        cloud = KnackCloudClient(baseURL: AppConfig.cloudURL, store: KeychainSessionStore())
        usage = UsageLog(fileURL: AppConfig.applicationSupport.appendingPathComponent("usage.json"))
        styleSamples = StyleSampleStore(fileURL: AppConfig.applicationSupport.appendingPathComponent("style-samples.json"))
        catalog = Catalog.bundled()
        isSignedIn = cloud.isSignedIn
        onboardingComplete = defaults.bool(forKey: Keys.onboardingComplete)
        givenName = defaults.string(forKey: Keys.givenName)
        #if DEBUG
        let direct = defaults.bool(forKey: Keys.useDirectProvider)
        useDirectProvider = direct
        router = Self.makeRouter(cloud: cloud, usage: usage, direct: direct)
        #else
        router = Self.makeRouter(cloud: cloud, usage: usage, direct: false)
        #endif
        skillHost = SkillHost(styleSamples: styleSamples)
        HotkeyService.register { [weak self] id in self?.runHotkey(id) }
    }

    private static func makeRouter(cloud: KnackCloudClient, usage: UsageLog, direct: Bool) -> ModelRouter {
        #if DEBUG
        if direct, let tiers = AppConfig.bundledTierMap() {
            let provider = DirectOpenRouterProvider(apiKey: {
                guard let key = DeveloperKeyStore.key else { throw KnackError.notSignedIn }
                return key
            }, tiers: tiers)
            return ModelRouter(provider: provider, usage: usage)
        }
        #endif
        return ModelRouter(provider: KnackCloudProvider(client: cloud), usage: usage)
    }

    var needsOnboarding: Bool { !isSignedIn || !onboardingComplete }

    // MARK: Skills

    /// The runtime services for a skill, limited to what its manifest declares.
    func context(for manifest: SkillManifest) -> SkillContext {
        SkillContext(manifest: manifest, services: RuntimeServices(
            router: router, selection: selection, imageInput: imageInput, notifications: notifications))
    }

    /// Global shortcut pressed. Ignored for disabled skills and before sign-in.
    func runHotkey(_ skillID: String) {
        guard !needsOnboarding, registry.isEnabled(skillID),
              let manifest = registry.manifest(id: skillID), let skill = skillHost.skill(skillID) else { return }
        Task {
            await skill.handleHotkey(context: context(for: manifest))
            await refreshUsage()
        }
    }

    /// Opens a skill: its window, or (for panel skills) the panel with no input.
    func open(_ skillID: String) {
        guard let manifest = registry.manifest(id: skillID), registry.isEnabled(skillID) else {
            detailSkillID = skillID
            section = .discover
            openHomeAction?()
            return
        }
        if skillHost.hasWindow(manifest) {
            openWindowAction?(skillID)
            NSApp.activate(ignoringOtherApps: true)
        } else if let skill = skillHost.skill(skillID) {
            Task { await skill.handleRoute(AskRoute(skillId: skillID, input: ""), context: context(for: manifest)) }
        }
    }

    enum AskOutcome: Equatable { case routed(String), noMatch }

    /// ⌘K: route a sentence to an installed skill with its input pre-filled. Never answers freely.
    func ask(_ sentence: String) async -> AskOutcome {
        let active = registry.active
        let routerModel = try? context(for: AskRouter.manifest).model()
        guard let route = try? await AskRouter.route(sentence, skills: active, model: routerModel),
              let manifest = registry.manifest(id: route.skillId) else { return .noMatch }
        if skillHost.hasWindow(manifest) {
            openWindowAction?(route.skillId)
        } else if let skill = skillHost.skill(route.skillId) {
            await skill.handleRoute(route, context: context(for: manifest))
        }
        return .routed(manifest.name)
    }

    // MARK: Account

    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential) async throws {
        guard let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
            throw KnackError.unauthorized
        }
        if let name = credential.fullName?.givenName, !name.isEmpty { givenName = name }
        _ = try await cloud.signInWithApple(identityToken: token)
        didSignIn()
    }

    /// Staging/debug test account tied to this Mac.
    func devSignIn() async throws {
        let defaults = UserDefaults.standard
        let deviceID = defaults.string(forKey: Keys.devDeviceID) ?? UUID().uuidString
        defaults.set(deviceID, forKey: Keys.devDeviceID)
        _ = try await cloud.devSignIn(deviceId: deviceID)
        didSignIn()
    }

    private func didSignIn() {
        isSignedIn = true
        accountError = nil
        Task { await refreshAccount() }
    }

    func signOut() {
        cloud.signOut()
        isSignedIn = false
        account = nil
        onboardingComplete = false
    }

    func refreshAccount() async {
        guard isSignedIn else { return }
        do {
            account = try await cloud.me()
            accountError = nil
        } catch let error as KnackError {
            accountError = error
            if error == .notSignedIn { isSignedIn = false }
        } catch {
            accountError = .server
        }
    }

    func refreshUsage() async {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        weekCounts = await usage.runCounts(since: weekAgo)
    }

    func clearHistory() async {
        await usage.clear()
        await refreshUsage()
    }

    func clearStyleSamples() async {
        await styleSamples.clear()
    }

    /// Successful runs this week for one skill.
    func weekCount(_ skillID: String) -> Int { weekCounts[skillID] ?? 0 }

    // MARK: URLs

    /// `knack://open/<skill-id>` (app shims, Phase 2) and `knack://account/refresh` (after a top-up).
    func handleURL(_ url: URL) {
        guard url.scheme == "knack" else { return }
        switch url.host {
        case "account":
            Task { await refreshAccount() }
        case "open":
            let id = url.pathComponents.dropFirst().first ?? ""
            if registry.manifest(id: id) != nil { open(id) }
        default:
            break
        }
    }
}
