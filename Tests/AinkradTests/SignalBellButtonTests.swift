import Testing
@testable import Ainkrad

@Suite("SignalBellButton badge")
struct SignalBellButtonTests {
    @Test("the badge appears only when something is unread")
    func badgeVisibility() {
        #expect(SignalBellButton.badgeText(0) == nil)
        #expect(SignalBellButton.badgeText(1) == "1")
        #expect(SignalBellButton.badgeText(42) == "42")
    }

    @Test("the badge caps so it cannot widen the top bar")
    func badgeCaps() {
        #expect(SignalBellButton.badgeText(99) == "99")
        #expect(SignalBellButton.badgeText(100) == "99+")
        #expect(SignalBellButton.badgeText(12_345) == "99+")
    }
}
