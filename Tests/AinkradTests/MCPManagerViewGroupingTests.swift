import Testing
@testable import Ainkrad

@Suite("MCPManagerView grouping")
struct MCPManagerViewGroupingTests {
    let configs = [
        MCPServerConfig(id: "brave", displayName: "Brave", transport: .stdio,
                        command: "/usr/bin/brave", enabled: true, trusted: false),
        MCPServerConfig(id: "gitmage", displayName: "Git Mage", transport: .inProcess,
                        enabled: true, trusted: false, appID: "gitmage"),
        MCPServerConfig(id: "terminal", displayName: "Terminal", transport: .inProcess,
                        enabled: true, trusted: true, appID: "terminal"),
    ]

    @Test("in-process configs are grouped as apps")
    func appConfigsAreInProcessOnly() {
        #expect(MCPManagerView.appConfigs(from: configs).map(\.id) == ["gitmage", "terminal"])
    }

    @Test("every other transport stays in the external group")
    func externalConfigsExcludeApps() {
        #expect(MCPManagerView.externalConfigs(from: configs).map(\.id) == ["brave"])
    }

    @Test("the two groups partition the configs with no loss or overlap")
    func groupsPartition() {
        let app = MCPManagerView.appConfigs(from: configs).map(\.id)
        let external = MCPManagerView.externalConfigs(from: configs).map(\.id)
        #expect(Set(app).isDisjoint(with: Set(external)))
        #expect(Set(app).union(external) == Set(configs.map(\.id)))
    }

    @Test("the app and external trust copy differ")
    func trustHelpDiffersByContext() {
        #expect(MCPManagerView.appTrustHelp != MCPManagerView.externalTrustHelp)
    }

    @Test("only the app variant discloses the in-process/live-state grant")
    func trustHelpAppMentionsInProcess() {
        #expect(MCPManagerView.appTrustHelp.contains("in-process"))
        #expect(MCPManagerView.appTrustHelp.contains("live state"))
        #expect(!MCPManagerView.externalTrustHelp.contains("in-process"))
    }

    @Test("both variants disclose auto-approval without prompting and the irreversible-action gate")
    func trustHelpBothDiscloseAutoApproveAndGate() {
        for help in [MCPManagerView.appTrustHelp, MCPManagerView.externalTrustHelp] {
            #expect(help.contains("without prompting"))
            #expect(help.contains("Irreversible actions still require your confirmation"))
        }
    }
}
