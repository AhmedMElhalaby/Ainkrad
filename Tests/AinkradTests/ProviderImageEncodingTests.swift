import Foundation
import Testing
@testable import Ainkrad

@Suite("Provider image encoding")
struct ProviderImageEncodingTests {
    @Test func openAIEncodesImageURLBlock() {
        let msg = AgentMessage(role: .user, content: [.image(mediaType: "image/png", base64: "AAAA"), .text("what is this")])
        let wire = OpenAICompatibleProvider.wireContentForTesting(msg)
        // Expect a content array carrying an image_url data URI.
        #expect(wire.contains { ($0["type"] as? String) == "image_url" })
    }
}
