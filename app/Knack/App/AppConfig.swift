import Foundation
import KnackCore

enum AppConfig {
    /// Knack Cloud base URL, from the `KNACK_CLOUD_URL` build setting via Info.plist.
    static var cloudURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "KnackCloudURL") as? String ?? ""
        return URL(string: raw) ?? URL(string: "http://localhost:8787")!
    }

    /// Shows "Use a test account" on the sign-in screen. On for Debug and staging builds
    /// (`KNACK_ALLOW_DEV_SIGN_IN`); the server must also have `ALLOW_DEV_AUTH=true`.
    static var allowsDevSignIn: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "KnackAllowDevSignIn") as? String) == "YES"
    }

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Knack", isDirectory: true)
    }

    static var bundledSkillsDirectory: URL {
        Bundle.main.resourceURL!.appendingPathComponent("Skills", isDirectory: true)
    }

    #if DEBUG
    /// Tier → model map for the DEBUG-only direct OpenRouter provider.
    static func bundledTierMap() -> TierMap? {
        guard let url = Bundle.main.url(forResource: "ModelTiers", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? TierMap.load(from: data)
    }
    #endif
}
