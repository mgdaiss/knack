import Foundation
import KnackCore

final class UserDefaultsInstallStateStore: InstallStateStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let installedKey = "skills.installed"
    private let disabledKey = "skills.disabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func installedIDs() -> Set<String>? {
        defaults.stringArray(forKey: installedKey).map(Set.init)
    }

    func setInstalledIDs(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: installedKey)
    }

    func disabledIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: disabledKey) ?? [])
    }

    func setDisabledIDs(_ ids: Set<String>) {
        defaults.set(ids.sorted(), forKey: disabledKey)
    }
}
