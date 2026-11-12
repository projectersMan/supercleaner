import XCTest
@testable import CleanerCore

@MainActor final class ApplicationQuitServiceTests: XCTestCase {
    private func application(system: Bool = false) -> InstalledApplication {
        .init(bundleURL: URL(fileURLWithPath: "/Applications/Example.app"),
              bundleIdentifier: "test.example", name: "Example", version: nil, isRunning: true, isSystem: system)
    }

    func testQuitOnlyExactInstalledCopyAndIdentifier() async {
        let target = QuitProcess()
        let copy = QuitProcess(path: "/Users/tester/Applications/Example.app")
        let unrelated = QuitProcess(identifier: "test.other")
        let result = await ApplicationQuitService.quit(application(), processes: [target, copy, unrelated], currentPID: 99, pause: {})
        XCTAssertEqual(result, .terminated)
        XCTAssertEqual(target.requests, 1)
        XCTAssertEqual(copy.requests, 0)
        XCTAssertEqual(unrelated.requests, 0)
    }

    func testSelfAndSystemCannotBeQuit() async {
        for (system, pid) in [(true, Int32(99)), (false, Int32(42))] {
            let process = QuitProcess()
            let result = await ApplicationQuitService.quit(application(system: system), processes: [process], currentPID: pid, pause: {})
            XCTAssertEqual(result, .protectedApplication)
            XCTAssertEqual(process.requests, 0)
        }
    }

    func testQuitRequestDoesNotMeanAppHasExited() async {
        let process = QuitProcess()
        process.exitOnRequest = false
        let result = await ApplicationQuitService.quit(application(), processes: [process], currentPID: 99, pause: {})
        XCTAssertEqual(result, .stillRunning)
        XCTAssertEqual(process.requests, 1)
        XCTAssertFalse(process.isTerminated)
    }

    func testRefusalDoesNotRetryOrForceQuit() async {
        let process = QuitProcess()
        process.acceptsRequest = false
        let result = await ApplicationQuitService.quit(application(), processes: [process], currentPID: 99, pause: {})
        XCTAssertEqual(result, .refused)
        XCTAssertEqual(process.requests, 1)
        XCTAssertFalse(process.isTerminated)
    }

    func testWaitsForActualExitAndHandlesAlreadyExitedProcess() async {
        let process = QuitProcess()
        process.exitOnRequest = false
        let result = await ApplicationQuitService.quit(application(), processes: [process], currentPID: 99,
            pause: { process.isTerminated = true })
        XCTAssertEqual(result, .terminated)
        let alreadyExited = await ApplicationQuitService.quit(application(), processes: [process], currentPID: 99, pause: {})
        XCTAssertEqual(alreadyExited, .notRunning)
        XCTAssertEqual(process.requests, 1)
    }
}

@MainActor private final class QuitProcess: ApplicationQuitProcess {
    let bundleURL: URL?
    let bundleIdentifier: String?
    let processIdentifier: Int32 = 42
    var isTerminated = false
    var exitOnRequest = true
    var acceptsRequest = true
    var requests = 0
    init(path: String = "/Applications/Example.app", identifier: String = "test.example") {
        bundleURL = URL(fileURLWithPath: path)
        bundleIdentifier = identifier
    }
    func terminate() -> Bool {
        requests += 1
        if acceptsRequest && exitOnRequest { isTerminated = true }
        return acceptsRequest
    }
}
