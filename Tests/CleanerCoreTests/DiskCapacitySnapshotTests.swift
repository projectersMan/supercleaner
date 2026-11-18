import Darwin
import Foundation
import XCTest
@testable import CleanerCore

final class DiskCapacitySnapshotTests: XCTestCase {
    private var fixtureDirectory: URL?

    override func tearDownWithError() throws {
        if let fixtureDirectory {
            try FileManager.default.removeItem(at: fixtureDirectory)
        }
        try super.tearDownWithError()
    }

    func testSnapshotCalculatesUsedCapacityAndPreservesMeasurementContext() throws {
        let volumeURL = URL(fileURLWithPath: "/Volumes/Test")
        let recordedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try XCTUnwrap(DiskCapacitySnapshot(
            volumeURL: volumeURL,
            totalBytes: 1_000,
            availableBytes: 400,
            recordedAt: recordedAt
        ))

        XCTAssertEqual(snapshot.volumeURL, volumeURL)
        XCTAssertEqual(snapshot.recordedAt, recordedAt)
        XCTAssertEqual(snapshot.totalBytes, 1_000)
        XCTAssertEqual(snapshot.availableBytes, 400)
        XCTAssertEqual(snapshot.usedBytes, 600)
        XCTAssertEqual(snapshot.usedFraction, 0.6, accuracy: 0.000_001)
    }

    func testSnapshotAcceptsFullAndEmptyVolumes() throws {
        let volumeURL = URL(fileURLWithPath: "/Volumes/Test")
        let recordedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let full = try XCTUnwrap(DiskCapacitySnapshot(
            volumeURL: volumeURL,
            totalBytes: 1_000,
            availableBytes: 0,
            recordedAt: recordedAt
        ))
        let empty = try XCTUnwrap(DiskCapacitySnapshot(
            volumeURL: volumeURL,
            totalBytes: 1_000,
            availableBytes: 1_000,
            recordedAt: recordedAt
        ))

        XCTAssertEqual(full.usedBytes, 1_000)
        XCTAssertEqual(full.usedFraction, 1)
        XCTAssertEqual(empty.usedBytes, 0)
        XCTAssertEqual(empty.usedFraction, 0)
    }

    func testSnapshotRejectsZeroAndInconsistentCapacity() {
        let volumeURL = URL(fileURLWithPath: "/Volumes/Test")
        let recordedAt = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertNil(DiskCapacitySnapshot(
            volumeURL: volumeURL,
            totalBytes: 0,
            availableBytes: 0,
            recordedAt: recordedAt
        ))
        XCTAssertNil(DiskCapacitySnapshot(
            volumeURL: volumeURL,
            totalBytes: UInt64.max - 1,
            availableBytes: UInt64.max,
            recordedAt: recordedAt
        ))
    }

    func testSnapshotSupportsLargestCapacityWithoutOverflow() throws {
        let snapshot = try XCTUnwrap(DiskCapacitySnapshot(
            volumeURL: URL(fileURLWithPath: "/Volumes/Test"),
            totalBytes: UInt64.max,
            availableBytes: 1,
            recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))

        XCTAssertEqual(snapshot.usedBytes, UInt64.max - 1)
        XCTAssertTrue(snapshot.usedFraction.isFinite)
        XCTAssertGreaterThan(snapshot.usedFraction, 0)
        XCTAssertLessThanOrEqual(snapshot.usedFraction, 1)
    }

    func testReaderMeasuresTheMountedVolumeContainingAnExistingDirectory() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("local-ai-projects-disk/fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fixtureDirectory = directory
        let before = Date()

        guard case let .available(snapshot) = DiskCapacityReader.read(at: directory) else {
            XCTFail("An existing local directory must provide its volume capacity")
            return
        }

        XCTAssertGreaterThan(snapshot.totalBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.availableBytes, snapshot.totalBytes)
        XCTAssertEqual(snapshot.usedBytes + snapshot.availableBytes, snapshot.totalBytes)
        XCTAssertTrue(snapshot.volumeURL.isFileURL)
        XCTAssertNotEqual(snapshot.volumeURL.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.volumeURL.path))
        XCTAssertGreaterThanOrEqual(snapshot.recordedAt, before)
        XCTAssertLessThanOrEqual(snapshot.recordedAt, Date())
    }

    func testReaderReportsMissingPathInsteadOfSuccessfulZeroCapacity() {
        let missing = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("local-ai-projects-disk/fixtures", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        guard case let .unavailable(error) = DiskCapacityReader.read(at: missing) else {
            XCTFail("A missing directory must report an error")
            return
        }
        XCTAssertEqual(error, ENOENT)
    }

    func testReaderRejectsNonFileURLs() throws {
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/volume"))

        guard case let .unavailable(error) = DiskCapacityReader.read(at: remoteURL) else {
            XCTFail("A non-file URL must report an error")
            return
        }
        XCTAssertEqual(error, EINVAL)
    }

    func testReaderRejectsEmbeddedNullInsteadOfReadingAPrefixPath() {
        let invalidURL = URL(fileURLWithPath: "/\0missing")

        guard case let .unavailable(error) = DiskCapacityReader.read(at: invalidURL) else {
            XCTFail("An embedded null must not truncate into an existing path")
            return
        }
        XCTAssertEqual(error, EINVAL)
    }
}
