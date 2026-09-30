import Foundation

/// The single list of capabilities a manifest may name, each with the sentence shown on the install screen.
/// Add new capabilities here and nowhere else.
public enum PermissionCatalog {
    public struct Entry: Sendable, Equatable {
        /// Shown under "Can" when granted.
        public let can: String
        /// Shown under "Never" when a skill promises not to touch it.
        public let never: String
        /// Whether a manifest may request it in Phase 1. Others are only valid in `never`.
        public let grantable: Bool
    }

    public static let entries: [Capability: Entry] = [
        .selectionRead: Entry(
            can: "Read the text you've selected, only when you press its shortcut",
            never: "Read the text you've selected",
            grantable: true),
        .selectionReplace: Entry(
            can: "Replace the text you've selected, only when you say so",
            never: "Change text in your apps",
            grantable: true),
        .imageInput: Entry(
            can: "See photos you choose to give it",
            never: "See your photos",
            grantable: true),
        .modelText: Entry(
            can: "Send the text it's working on to Knack's AI",
            never: "Send anything to an AI",
            grantable: true),
        .modelVision: Entry(
            can: "Send the photos you give it to Knack's AI",
            never: "Send pictures to an AI",
            grantable: true),
        .notifications: Entry(
            can: "Send you a notification",
            never: "Send you notifications",
            grantable: true),
        "files.read": Entry(
            can: "Open your files",
            never: "Open or read your files",
            grantable: false),
        "email.read": Entry(
            can: "Read your email",
            never: "Read your email",
            grantable: false),
        "network.other": Entry(
            can: "Talk to other websites",
            never: "Talk to any website other than Knack",
            grantable: false),
        "screen.read": Entry(
            can: "See what's on your screen",
            never: "See what's on your screen",
            grantable: false),
    ]

    public static func entry(for capability: Capability) -> Entry? {
        entries[capability]
    }

    public static func canSentence(_ capability: Capability) -> String {
        entries[capability]?.can ?? capability.rawValue
    }

    public static func neverSentence(_ capability: Capability) -> String {
        entries[capability]?.never ?? capability.rawValue
    }
}
