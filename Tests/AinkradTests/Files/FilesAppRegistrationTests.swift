import Testing
import AinkradAppKit
@testable import Ainkrad

@MainActor
@Suite("FilesApp registration")
struct FilesAppRegistrationTests {
    @Test("declares its identity")
    func identity() {
        #expect(FilesApp.id == "files")
        #expect(FilesApp.displayName == "Files")
        #expect(FilesApp.icon == "folder")
    }
}
