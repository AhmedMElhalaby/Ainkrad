import Testing
import AinkradAppKit
@testable import Ainkrad

@MainActor
@Suite("HoardApp registration")
struct HoardAppRegistrationTests {
    @Test("declares its identity")
    func identity() {
        #expect(HoardApp.id == "hoard")
        #expect(HoardApp.displayName == "Hoard")
        #expect(HoardApp.icon == "folder")
    }
}
