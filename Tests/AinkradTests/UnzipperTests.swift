import Testing
import Foundation
@testable import Ainkrad

struct UnzipperTests {
    /// Zips a directory with `ditto -c -k` (test helper), then unzips it with
    /// the production DittoUnzipper and checks the contents survive.
    @Test("DittoUnzipper extracts a zip round-trip")
    func roundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let src = tmp.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "hello".data(using: .utf8)!.write(to: src.appendingPathComponent("a.txt"))

        let zip = tmp.appendingPathComponent("out.zip")
        let make = Process()
        make.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        make.arguments = ["-c", "-k", src.path, zip.path]
        try make.run(); make.waitUntilExit()
        #expect(make.terminationStatus == 0)

        let dest = tmp.appendingPathComponent("dest")
        try DittoUnzipper().unzip(zip, to: dest)
        let extracted = try String(contentsOf: dest.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(extracted == "hello")
    }
}
