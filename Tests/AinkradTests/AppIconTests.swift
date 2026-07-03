import Testing
@testable import Ainkrad

@Suite("App icon resolution")
struct AppIconTests {

    @Test("Auto follows the active theme")
    func autoFollowsTheme() {
        #expect(AppIconChoice.auto.resolvedIcon(for: .neonBlue) == .blue)
        #expect(AppIconChoice.auto.resolvedIcon(for: .cyberPurple) == .purple)
    }

    @Test("An explicit choice wins regardless of theme")
    func explicitChoiceWins() {
        #expect(AppIconChoice.blue.resolvedIcon(for: .cyberPurple) == .blue)
        #expect(AppIconChoice.purple.resolvedIcon(for: .neonBlue) == .purple)
    }

    @Test("Each resolved icon maps to its bundled asset")
    func resolvedIconAssetNames() {
        #expect(AppIcon.blue.assetName == "AppIcon-NeonBlue")
        #expect(AppIcon.purple.assetName == "AppIcon-CyberPurple")
    }
}
