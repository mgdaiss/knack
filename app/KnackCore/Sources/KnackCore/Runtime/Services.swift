import Foundation

// Service protocols a skill can be granted through `SkillContext`. Implementations live in the app
// (AppKit / Accessibility / UserNotifications); keeping the shapes here lets a future WKWebView
// bridge for third-party skills (SPEC §4.3) wrap the same services.

public protocol SelectionService: Sendable {
    /// The selected text in the frontmost app, or nil if nothing is selected.
    func readSelection() async throws -> String?
    /// Replaces the selection in the frontmost app.
    func replaceSelection(with text: String) async throws
}

public struct PickedImage: Sendable, Equatable {
    public let data: Data
    /// e.g. `image/jpeg`
    public let mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }

    public var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

public protocol ImageInputService: Sendable {
    /// Lets the user pick a photo (file picker, drop or Continuity Camera). Nil if cancelled.
    func pickImage() async throws -> PickedImage?
}

public protocol NotificationService: Sendable {
    func notify(title: String, body: String) async throws
}

/// Everything the runtime can offer. `SkillContext` hands out only what a manifest declares.
public struct RuntimeServices: Sendable {
    public var router: ModelRouter
    public var selection: (any SelectionService)?
    public var imageInput: (any ImageInputService)?
    public var notifications: (any NotificationService)?

    public init(router: ModelRouter, selection: (any SelectionService)? = nil, imageInput: (any ImageInputService)? = nil, notifications: (any NotificationService)? = nil) {
        self.router = router
        self.selection = selection
        self.imageInput = imageInput
        self.notifications = notifications
    }
}
