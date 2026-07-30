import Foundation
import Testing
@testable import Ainkrad
import AinkradAppKit

@Suite("Launch resolution")
struct LaunchResolutionTests {
    @Test func firstLaunchAdoptsTheDefaultVaultLocation() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let pointer = base.appendingPathComponent("pointer")
        let cache = base.appendingPathComponent("cache")
        let desired = base.appendingPathComponent("Ainkrad")

        let home = try LaunchHomeResolver.resolveOrAdopt(
            defaultVault: desired, pointerDirectory: pointer, cacheRoot: cache)

        #expect(home.vaultRoot.standardizedFileURL == desired.standardizedFileURL)
        #expect(FileManager.default.fileExists(
            atPath: desired.appendingPathComponent(".ainkrad-home").path))
    }

    /// The prohibited behaviour: a configured-but-unreachable vault must never
    /// silently become a fresh one somewhere else.
    @Test func aMissingVaultDoesNotSilentlyBecomeANewOne() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch2-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let pointer = base.appendingPathComponent("pointer")
        let cache = base.appendingPathComponent("cache")
        let vault = base.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try AinkradHome.adopt(vault, pointerDirectory: pointer, cacheRoot: cache)
        try FileManager.default.removeItem(at: vault)

        #expect(throws: LaunchHomeResolver.Failure.self) {
            _ = try LaunchHomeResolver.resolveOrAdopt(
                defaultVault: base.appendingPathComponent("Elsewhere"),
                pointerDirectory: pointer, cacheRoot: cache)
        }
    }

    /// A directory that exists but is not a home must not be re-adopted, and must
    /// not cause a fresh vault to appear elsewhere either.
    @Test func aForeignVaultThrows() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch3-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let pointer = base.appendingPathComponent("pointer")
        let cache = base.appendingPathComponent("cache")
        let vault = base.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try AinkradHome.adopt(vault, pointerDirectory: pointer, cacheRoot: cache)
        try FileManager.default.removeItem(at: vault.appendingPathComponent(".ainkrad-home"))

        #expect(throws: LaunchHomeResolver.Failure.self) {
            _ = try LaunchHomeResolver.resolveOrAdopt(
                defaultVault: base.appendingPathComponent("Elsewhere"),
                pointerDirectory: pointer, cacheRoot: cache)
        }
        #expect(!FileManager.default.fileExists(
            atPath: base.appendingPathComponent("Elsewhere").path))
    }

    /// A second launch resolves the pointer written by the first, rather than
    /// adopting anything new.
    @Test func aSecondLaunchResolvesTheExistingPointer() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch4-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let pointer = base.appendingPathComponent("pointer")
        let cache = base.appendingPathComponent("cache")
        let desired = base.appendingPathComponent("Ainkrad")

        let first = try LaunchHomeResolver.resolveOrAdopt(
            defaultVault: desired, pointerDirectory: pointer, cacheRoot: cache)
        let second = try LaunchHomeResolver.resolveOrAdopt(
            defaultVault: base.appendingPathComponent("Elsewhere"),
            pointerDirectory: pointer, cacheRoot: cache)

        #expect(second.vaultRoot.standardizedFileURL == first.vaultRoot.standardizedFileURL)
        #expect(!FileManager.default.fileExists(
            atPath: base.appendingPathComponent("Elsewhere").path))
    }
}
