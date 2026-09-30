import Foundation
import Observation

/// Remembers which skills are installed and enabled.
public protocol InstallStateStore: Sendable {
    func installedIDs() -> Set<String>?
    func setInstalledIDs(_ ids: Set<String>)
    func disabledIDs() -> Set<String>
    func setDisabledIDs(_ ids: Set<String>)
}

public final class InMemoryInstallStateStore: InstallStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var installed: Set<String>?
    private var disabled: Set<String> = []
    public init(installed: Set<String>? = nil) { self.installed = installed }
    public func installedIDs() -> Set<String>? { lock.withLock { installed } }
    public func setInstalledIDs(_ ids: Set<String>) { lock.withLock { installed = ids } }
    public func disabledIDs() -> Set<String> { lock.withLock { disabled } }
    public func setDisabledIDs(_ ids: Set<String>) { lock.withLock { disabled = ids } }
}

/// Loads bundled manifests (`<dir>/<SkillName>/skill.json`) and tracks install/enable state.
@MainActor
@Observable
public final class SkillRegistry {
    public private(set) var manifests: [SkillManifest] = []
    public private(set) var installedIDs: Set<String> = []
    public private(set) var disabledIDs: Set<String> = []
    /// Manifests that failed to load, with the reason. Shown in DEBUG builds only.
    public private(set) var loadErrors: [String] = []

    @ObservationIgnored private let store: any InstallStateStore

    public init(store: any InstallStateStore) {
        self.store = store
    }

    /// Loads every `skill.json` one level below `directory`. First launch installs all bundled skills.
    public func load(from directory: URL) {
        var loaded: [SkillManifest] = []
        var errors: [String] = []
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let file = folder.appendingPathComponent("skill.json")
            guard let data = try? Data(contentsOf: file) else { continue }
            do {
                loaded.append(try SkillManifest.load(from: data))
            } catch {
                errors.append("\(folder.lastPathComponent): \(error)")
            }
        }
        register(loaded)
        loadErrors = errors
    }

    public func register(_ loaded: [SkillManifest]) {
        manifests = loaded
        let known = Set(loaded.map(\.id))
        installedIDs = (store.installedIDs() ?? known).intersection(known)
        disabledIDs = store.disabledIDs()
        store.setInstalledIDs(installedIDs)
    }

    public func manifest(id: String) -> SkillManifest? {
        manifests.first { $0.id == id }
    }

    public var installed: [SkillManifest] {
        manifests.filter { installedIDs.contains($0.id) }
    }

    /// Installed and not disabled.
    public var active: [SkillManifest] {
        installed.filter { !disabledIDs.contains($0.id) }
    }

    public func isInstalled(_ id: String) -> Bool { installedIDs.contains(id) }
    public func isEnabled(_ id: String) -> Bool { isInstalled(id) && !disabledIDs.contains(id) }

    public func install(_ id: String) {
        guard manifest(id: id) != nil else { return }
        installedIDs.insert(id)
        store.setInstalledIDs(installedIDs)
    }

    public func uninstall(_ id: String) {
        installedIDs.remove(id)
        store.setInstalledIDs(installedIDs)
    }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        if enabled { disabledIDs.remove(id) } else { disabledIDs.insert(id) }
        store.setDisabledIDs(disabledIDs)
    }
}
