import Testing
import Foundation
@testable import Ainkrad

@Suite struct LoopbackCallbackServerTests {
    @Test func parsesCodeAndStateFromQuery() throws {
        let r = try LoopbackCallbackServer.parseCallback(query: "code=ABC&state=XYZ")
        #expect(r == CallbackResult(code: "ABC", state: "XYZ"))
    }

    @Test func rejectsQueryMissingCode() {
        #expect(throws: LoopbackError.malformedCallback) {
            _ = try LoopbackCallbackServer.parseCallback(query: "state=XYZ")
        }
    }
}
