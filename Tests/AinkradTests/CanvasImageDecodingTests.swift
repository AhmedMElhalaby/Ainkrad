import Testing
import Foundation
@testable import Ainkrad

@Suite("CanvasImageDecoding")
struct CanvasImageDecodingTests {
    private let pngB64 = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).base64EncodedString()

    @Test func parsesBase64DataURL() {
        let body = "data:image/jpeg;base64,\(pngB64)"
        #expect(CanvasImageDecoding.base64Payload(body) == Data(base64Encoded: pngB64))
    }

    @Test func rejectsNonDataAndMalformed() {
        #expect(CanvasImageDecoding.base64Payload("https://example.com/x.png") == nil)
        #expect(CanvasImageDecoding.base64Payload("data:image/png,notbase64") == nil) // no ;base64
        #expect(CanvasImageDecoding.base64Payload("data:image/png;base64,") == nil)   // empty payload
        #expect(CanvasImageDecoding.base64Payload("") == nil)
    }
}
