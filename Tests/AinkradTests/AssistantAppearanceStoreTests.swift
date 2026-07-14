import Foundation
import SwiftUI
import Testing
@testable import Ainkrad

@Suite("AssistantAppearanceStore")
@MainActor
struct AssistantAppearanceStoreTests {
    @Test func defaultsToOpaqueNoBlur() {
        let store = AssistantAppearanceStore(persistence: InMemoryPersistenceStore())
        #expect(store.surfaceOpacity == 1.0)
        #expect(store.blurEnabled == false)
    }

    @Test func clampsSurfaceOpacityToUnitRange() {
        let store = AssistantAppearanceStore(persistence: InMemoryPersistenceStore())
        store.setSurfaceOpacity(1.7)
        #expect(store.surfaceOpacity == 1.0)
        store.setSurfaceOpacity(-0.4)
        #expect(store.surfaceOpacity == 0.0)
        store.setSurfaceOpacity(0.55)
        #expect(store.surfaceOpacity == 0.55)
    }

    @Test func persistsAcrossReload() {
        let persistence = InMemoryPersistenceStore()
        let store = AssistantAppearanceStore(persistence: persistence)
        store.setSurfaceOpacity(0.6)
        store.setBlurEnabled(true)

        let reloaded = AssistantAppearanceStore(persistence: persistence)
        #expect(reloaded.surfaceOpacity == 0.6)
        #expect(reloaded.blurEnabled == true)
    }
}

@Suite("AssistantApp.surfaceFill")
@MainActor
struct AssistantSurfaceFillTests {
    @Test func opaqueAtFullOpacityReturnsNil() {
        #expect(AssistantApp.surfaceFill(opacity: 1.0, base: .white) == nil)
    }

    @Test func translucentBelowFullOpacityReturnsAColor() {
        #expect(AssistantApp.surfaceFill(opacity: 0.5, base: .white) != nil)
        #expect(AssistantApp.surfaceFill(opacity: 0.0, base: .white) != nil)
    }
}
