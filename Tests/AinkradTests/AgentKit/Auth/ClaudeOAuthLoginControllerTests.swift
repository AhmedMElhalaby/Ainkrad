import Testing
import Foundation
@testable import Ainkrad

@Suite struct ClaudeOAuthLoginControllerTests {
    @Test func parsesHashDelimitedCodeState() {
        let r = ClaudeOAuthLoginController.parsePastedCode("THECODE#THESTATE")
        #expect(r == CallbackResult(code: "THECODE", state: "THESTATE"))
    }

    @Test func parsesFullRedirectURLPaste() {
        let r = ClaudeOAuthLoginController.parsePastedCode("http://localhost:53692/callback?code=C&state=S")
        #expect(r == CallbackResult(code: "C", state: "S"))
    }

    @Test func returnsNilForEmpty() {
        #expect(ClaudeOAuthLoginController.parsePastedCode("   ") == nil)
    }
}
