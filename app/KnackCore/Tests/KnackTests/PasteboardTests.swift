import Foundation
import Testing
@testable import KnackCore

final class FakePasteboard: PasteboardAccess, @unchecked Sendable {
    private(set) var changeCount = 0
    var items: [[String: Data]] = []

    func readItems() -> [[String: Data]] { items }
    func writeItems(_ items: [[String: Data]]) { self.items = items; changeCount += 1 }
    func readString() -> String? { items.first?["public.utf8-plain-text"].map { String(decoding: $0, as: UTF8.self) } }
    func writeString(_ string: String) { writeItems([["public.utf8-plain-text": Data(string.utf8)]]) }
}

struct Boom: Error {}

@Suite("Pasteboard save/restore")
struct PasteboardTests {
    let original: [[String: Data]] = [
        ["public.utf8-plain-text": Data("user's clipboard".utf8), "public.rtf": Data("{\\rtf1 x}".utf8)],
        ["public.png": Data([0x89, 0x50, 0x4E, 0x47])],
    ]

    @Test func restoresEveryItemAndTypeAfterUse() async throws {
        let pb = FakePasteboard()
        pb.items = original
        let copied = await pb.preservingContents { () async -> String? in
            pb.writeString("selected text")
            return pb.readString()
        }
        #expect(copied == "selected text")
        #expect(pb.items == original)
    }

    @Test func restoresOnError() async {
        let pb = FakePasteboard()
        pb.items = original
        await #expect(throws: Boom.self) {
            try await pb.preservingContents { () async throws -> Void in
                pb.writeString("rewrite")
                throw Boom()
            }
        }
        #expect(pb.items == original)
    }

    @Test func restoresOnCancel() async {
        let pb = FakePasteboard()
        pb.items = original
        let task = Task {
            try await pb.preservingContents { () async throws -> Void in
                pb.writeString("rewrite")
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        _ = await task.result
        #expect(pb.items == original)
    }

    @Test func restoresAnEmptyPasteboard() async {
        let pb = FakePasteboard()
        await pb.preservingContents { () async -> Void in pb.writeString("x") }
        #expect(pb.items.isEmpty)
    }
}
