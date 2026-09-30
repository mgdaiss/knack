import KnackCore

/// Errors in the helper's own voice (SPEC §3.2). Raw HTTP never reaches the UI.
enum CharacterVoice {
    static func says(_ manifest: SkillManifest, _ error: Error) -> String {
        "\(manifest.name) says: \(line(manifest, error))"
    }

    static func line(_ manifest: SkillManifest, _ error: Error) -> String {
        guard let error = error as? KnackError else { return KnackError.server.friendlyMessage }
        switch (manifest.id, error) {
        case ("com.knack.fridge-chef", .modelUnavailable): return "My oven's cooling down. Try again in a moment."
        case ("com.knack.fridge-chef", .invalidResponse): return "I got my recipes in a muddle. Let's try that again."
        case ("com.knack.say-it-better", .modelUnavailable): return "I'm lost for words for a second. Try again?"
        case ("com.knack.explain-this", .modelUnavailable): return "I need a moment to think. Try again shortly."
        case (_, .permissionDenied(let c)) where c == .selectionRead || c == .selectionReplace:
            return "I need Accessibility access to see your selection. Turn it on in Settings."
        default: return error.friendlyMessage
        }
    }
}
