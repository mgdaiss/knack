import KnackCore
import SwiftUI

/// A skill's character on its colored rounded tile (the `<asset>.svg` art already includes the tile).
struct CharacterTile: View {
    let manifest: SkillManifest
    var size: CGFloat = Theme.Size.tile

    var body: some View {
        Image(manifest.character.asset)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * Theme.Radius.tile / Theme.Size.tile, style: .continuous))
            .themeShadow(Theme.Shadows.tile)
            .accessibilityLabel(manifest.name)
    }
}

/// A character glyph on a custom background, e.g. a tinted card.
struct CharacterGlyph: View {
    let manifest: SkillManifest
    var size: CGFloat = Theme.Size.smallTile

    var body: some View {
        Image("\(manifest.character.asset)-glyph")
            .resizable()
            .interpolation(.high)
            .frame(width: size * 0.85, height: size * 0.85)
            .frame(width: size, height: size)
            .background(Color(hexString: manifest.character.color) ?? Theme.Colors.indigo,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.smallTile, style: .continuous))
            .accessibilityLabel(manifest.name)
    }
}

/// Long-tail skills without a character yet: a pastel circle with two ink eyes (SPEC §7).
struct BlobBuddy: View {
    let color: Color
    var size: CGFloat = Theme.Size.blob
    var label: String

    var body: some View {
        ZStack {
            Circle().fill(color)
            HStack(spacing: size * 0.22) {
                Circle().fill(Theme.Colors.blobEye).frame(width: Theme.Size.blobEye, height: Theme.Size.blobEye)
                Circle().fill(Theme.Colors.blobEye).frame(width: Theme.Size.blobEye, height: Theme.Size.blobEye)
            }
            .offset(y: -size * 0.04)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}
