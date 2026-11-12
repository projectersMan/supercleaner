import XCTest
@testable import CleanerCore

final class FileIdentityParityTests: XCTestCase {
    func testNativeIdentityMatchesFoundationForFilesDirectoriesAndLinks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("identity-parity-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("payload")
        try Data([1, 2, 3]).write(to: file)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let broken = root.appendingPathComponent("broken")
        try FileManager.default.createSymbolicLink(atPath: broken.path, withDestinationPath: "missing")
        for url in [root, file, link, broken] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let actual = try await LocalFileSystem().identity(at: url)
            XCTAssertEqual(actual.device, (attributes[.systemNumber] as? NSNumber)?.uint64Value)
            XCTAssertEqual(actual.inode, (attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
            XCTAssertEqual(actual.size, (attributes[.size] as? NSNumber)?.uint64Value)
            XCTAssertEqual(actual.modificationTime, Int64((attributes[.modificationDate] as! Date).timeIntervalSince1970))
            let expected: FileIdentity.Kind = url == root ? .directory : (url == file ? .file : .symbolicLink)
            XCTAssertEqual(actual.kind, expected)
        }
        do { _ = try await LocalFileSystem().identity(at: root.appendingPathComponent("missing")); XCTFail("Missing entries must fail") }
        catch FileSystemError.missing { }
    }
}
