import Testing
import AinkradAppKit
@testable import Ainkrad

@Suite("Status color bridge")
struct StatusColorBridgeTests {
    @Test("every theme carries distinct status colors through the SDK bridge")
    func bridged() {
        for theme in Theme.allCases {
            let t = HostThemeTokens(from: theme)
            #expect(t.success != t.danger)
            #expect(t.warning != t.background)
        }
    }
}
