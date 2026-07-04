import Testing
@testable import Ainkrad
@testable import AinkradAppKit

struct PluginValidatorTests {
    private func meta(id: String = "hello", api: Int = 1) -> PluginBundleMetadata {
        PluginBundleMetadata(appID: id, displayName: "Hello", iconSymbol: "hand.wave",
                             apiVersion: api, principalClassName: "HelloEntryPoint")
    }

    @Test("valid app ids pass, unsafe ones fail")
    func appID() {
        #expect(PluginValidator.isValidAppID("hello.world_1-2"))
        #expect(!PluginValidator.isValidAppID(""))
        #expect(!PluginValidator.isValidAppID("."))
        #expect(!PluginValidator.isValidAppID(".."))
        #expect(!PluginValidator.isValidAppID("../evil"))
        #expect(!PluginValidator.isValidAppID("a/b"))
    }

    @Test("valid metadata within API range passes")
    func metadataOK() {
        if case .success = PluginValidator.validate(meta(), minSupportedAPIVersion: 1) {}
        else { Issue.record("expected success") }
    }

    @Test("unsupported API version is rejected")
    func metadataBadAPI() {
        let r = PluginValidator.validate(meta(api: 999), minSupportedAPIVersion: 1)
        if case .failure(let rej) = r { #expect(rej.reason.contains("API version 999")) }
        else { Issue.record("expected failure") }
    }

    @Test("invalid app id is rejected")
    func metadataBadID() {
        let r = PluginValidator.validate(meta(id: "../x"), minSupportedAPIVersion: 1)
        if case .failure(let rej) = r { #expect(rej.reason == "invalid app id") }
        else { Issue.record("expected failure") }
    }
}
