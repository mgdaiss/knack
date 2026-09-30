import AppKit
import KnackCore
import UniformTypeIdentifiers

/// Photos for skills with `image.input`. Everything is re-encoded as a downsized JPEG, which also
/// drops location metadata, so only what the task needs is sent.
final class AppImageInput: ImageInputService, @unchecked Sendable {
    static let maxDimension: CGFloat = 1600

    func pickImage() async throws -> PickedImage? {
        let url: URL? = await MainActor.run {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.message = "Choose a photo of your fridge or pantry"
            return panel.runModal() == .OK ? panel.url : nil
        }
        guard let url else { return nil }
        return try await importImage(data: Data(contentsOf: url))
    }

    func importImage(data: Data) async throws -> PickedImage {
        guard let image = NSImage(data: data), let jpeg = Self.downsizedJPEG(image) else { throw KnackError.badRequest }
        return PickedImage(data: jpeg, mimeType: "image/jpeg")
    }

    static func downsizedJPEG(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let scale = min(1, maxDimension / max(width, height))
        let size = NSSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSImage(cgImage: cg, size: size).draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
