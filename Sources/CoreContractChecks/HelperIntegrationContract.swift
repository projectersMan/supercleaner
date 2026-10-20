import CleanerCore
import Darwin
import Foundation
import Security

func runHelperIntegrationContracts() async throws {
    let manager = FileManager.default
    let rootPath = "/private/tmp/supercleaner-helper-contract-" + UUID().uuidString
    let root = URL(fileURLWithPath: rootPath)
    defer { try? manager.removeItem(at: root) }
    let appRoot = rootPath + "/Applications"
    let home = rootPath + "/home"
    try manager.createDirectory(atPath: appRoot, withIntermediateDirectories: true)
    try manager.createDirectory(atPath: home, withIntermediateDirectories: true)
    let scope = try HelperFileScope(userID: getuid(), homePath: home, applicationsPath: appRoot)
    let operations = HelperFileOperations(scope: scope)
    let plan = UUID()
    let planDirectory = scope.quarantinePath + "/" + plan.uuidString
    try manager.createDirectory(atPath: planDirectory, withIntermediateDirectories: true)
    let source = appRoot + "/Example.app"
    let destination = planDirectory + "/" + UUID().uuidString + "-Example.app"
    try manager.createDirectory(atPath: source + "/Contents", withIntermediateDirectories: true)
    let payload = source + "/Contents/payload"
    try Data("fixture".utf8).write(to: URL(fileURLWithPath: payload))
    let identity = try operations.inspect(source)
    let localIdentity = try await LocalFileSystem().identity(at: URL(fileURLWithPath: source))
    require(identity == localIdentity, "fd identity must match executor's scanned identity")
    let expectedSigning = try HelperSigningIdentity(applicationIdentifier: "org.contract.SuperCleaner", teamIdentifier: "A1B2C3D4E5")
    var requirement: SecRequirement?
    let parsedRequirement = SecRequirementCreateWithString(expectedSigning.helperRequirement as CFString, [], &requirement)
    require(parsedRequirement == errSecSuccess, "team/identifier/entitlement requirement must parse using Security framework")
    require(expectedSigning.helperRequirement.contains("A1B2C3D4E5") && expectedSigning.callerRequirement.contains("org.contract.SuperCleaner"), "both XPC peers must be bound to exact identifiers and team")
    for invalid in ["com.example.SuperCleaner", "org.example.\" injected", ""] {
        do { _ = try HelperSigningIdentity(applicationIdentifier: invalid, teamIdentifier: "A1B2C3D4E5"); require(false, "invalid/helper example identity accepted") }
        catch is HelperClientError { }
    }
    let session = HelperAuthorizationSession()
    require(!session.isAuthorized && !HelperAuthorizationSession.validateExternalForm(nil), "no implicit authorization may be acquired")
    do { _ = try session.externalForm(); require(false, "unauthorized session yielded an external form") } catch HelperClientError.notAuthorized { }
    func token(_ operation: HelperOperation, identity: FileIdentity, uid: UInt32 = getuid(), planID: UUID? = nil) -> CapabilityToken {
        .init(planID: planID ?? plan, operationDigest: operation.digest, expiresAt: Date().addingTimeInterval(60), callerRequirement: expectedSigning.callerRequirement, identity: identity, callerUserID: uid)
    }
    let move = HelperOperation.moveToQuarantine(path: source, destination: destination)
    let denied = HelperRequestHandler(authorizer: .init(expectedCallerRequirement: expectedSigning.callerRequirement), authorizationCheck: { _ in false })
    let missingAuthorization = await denied.handle(try JSONEncoder().encode(HelperRequest(operation: move, token: token(move, identity: identity))), scope: scope)
    require(missingAuthorization.authorization == .rejected(.authorizationRequired) && manager.fileExists(atPath: source), "root handler must independently require operation authorization")
    let wrongUser = await denied.handle(try JSONEncoder().encode(HelperRequest(operation: move, token: token(move, identity: identity, uid: getuid() + 1))), scope: scope)
    require(wrongUser.authorization == .rejected(.callerMismatch), "another user cannot select this user's home or quarantine")
    for path in [source + "/../Other.app", appRoot + "/../System.app", "/System/Applications/Example.app", appRoot + "//Example.app", source + "\n"] {
        do { _ = try operations.inspect(path); require(false, "invalid path accepted by helper: \(path)") } catch { }
    }
    let wrongPlan = HelperOperation.moveToQuarantine(path: source, destination: destination)
    do { _ = try operations.perform(wrongPlan, token: token(wrongPlan, identity: identity, planID: UUID())); require(false, "cross-plan quarantine destination accepted") } catch HelperRejection.invalidPath { }

    let outside = rootPath + "/outside"
    try manager.createDirectory(atPath: outside, withIntermediateDirectories: true)
    let sentinel = outside + "/must-survive"
    try Data("outside untouched".utf8).write(to: URL(fileURLWithPath: sentinel))
    let linkedParent = appRoot + "/Linked"
    try manager.createSymbolicLink(atPath: linkedParent, withDestinationPath: outside)
    do { _ = try operations.inspect(linkedParent + "/Escape.app"); require(false, "symlink ancestor was followed") } catch { }
    let linkedApp = appRoot + "/Linked.app"
    try manager.createSymbolicLink(atPath: linkedApp, withDestinationPath: outside)
    let linkedID = try operations.inspect(linkedApp)
    let linkedMove = HelperOperation.moveToQuarantine(path: linkedApp, destination: destination)
    do { _ = try operations.perform(linkedMove, token: token(linkedMove, identity: linkedID)); require(false, "symlink application was moved as a privileged directory") } catch HelperRejection.invalidPath { }
    let linkedPlan = UUID()
    try manager.createSymbolicLink(atPath: scope.quarantinePath + "/" + linkedPlan.uuidString, withDestinationPath: outside)
    let escapedDestination = scope.quarantinePath + "/" + linkedPlan.uuidString + "/" + UUID().uuidString + "-Escape.app"
    let escape = HelperOperation.moveToQuarantine(path: source, destination: escapedDestination)
    do { _ = try operations.perform(escape, token: token(escape, identity: identity, planID: linkedPlan)); require(false, "quarantine symlink ancestor was followed") } catch { }

    let handler = HelperRequestHandler(authorizer: .init(expectedCallerRequirement: expectedSigning.callerRequirement), authorizationCheck: { $0 == Data("test-only-authorization".utf8) })
    let request = HelperRequest(operation: move, token: token(move, identity: identity), authorizationExternalForm: Data("test-only-authorization".utf8))
    let response = await handler.handle(try JSONEncoder().encode(request), scope: scope)
    require(response.authorization == .accepted && !manager.fileExists(atPath: source) && manager.fileExists(atPath: destination), "same root handler must perform authorized fd-relative move without root privileges in fixture")
    let replay = await handler.handle(try JSONEncoder().encode(request), scope: scope)
    require(replay.authorization != .accepted, "completed file mutation cannot be replayed")
    let restore = HelperOperation.restoreFromQuarantine(path: destination, destination: source)
    let movedIdentity = try operations.inspect(destination)
    try manager.createDirectory(atPath: source, withIntermediateDirectories: true)
    do { _ = try operations.perform(restore, token: token(restore, identity: movedIdentity)); require(false, "helper restore overwrote an existing app") } catch { }
    try manager.removeItem(atPath: source)
    _ = try operations.perform(restore, token: token(restore, identity: movedIdentity))
    require(manager.fileExists(atPath: payload) && !manager.fileExists(atPath: destination), "restore returns the same quarantined bundle without copy/chown")
    let stale = FileIdentity(device: identity.device, inode: identity.inode + 1, size: identity.size, modificationTime: identity.modificationTime, kind: .directory)
    do { _ = try operations.perform(move, token: token(move, identity: stale)); require(false, "identity replacement accepted") } catch HelperRejection.identityMismatch { }
    _ = try operations.perform(move, token: token(move, identity: identity))
    try manager.createSymbolicLink(atPath: destination + "/Contents/outside-link", withDestinationPath: outside)
    let purge = HelperOperation.purgeOwnedQuarantine(path: destination)
    _ = try operations.perform(purge, token: token(purge, identity: try operations.inspect(destination)))
    let remainingSentinel = try Data(contentsOf: URL(fileURLWithPath: sentinel))
    require(!manager.fileExists(atPath: destination) && remainingSentinel == Data("outside untouched".utf8), "recursive purge unlinks symlinks, never their target")
    let limitedItem = planDirectory + "/" + UUID().uuidString + "-Limited.app"
    try manager.createDirectory(atPath: limitedItem + "/a/b", withIntermediateDirectories: true)
    let limitedPurge = HelperOperation.purgeOwnedQuarantine(path: limitedItem)
    do { _ = try HelperFileOperations(scope: scope, maximumEntries: 1).perform(limitedPurge, token: token(limitedPurge, identity: try operations.inspect(limitedItem))); require(false, "purge entry budget ignored") } catch HelperRejection.executionFailed { }
    require(manager.fileExists(atPath: limitedItem) && manager.fileExists(atPath: sentinel), "partial bounded purge must retain its container and outside files")
    let oversized = await handler.handle(Data(repeating: 32, count: 65_537), scope: scope)
    require(oversized.authorization == .rejected(.unsupported), "XPC request size must be bounded before decoding")

    let inactive = AuthorizedApplicationOperations(session: session, registrationEnabled: { true }, identity: expectedSigning, client: NeverCalledHelperClient())
    let candidate = CleanupCandidate(url: URL(fileURLWithPath: "/Applications/Example.app"), displayName: "Example", category: .application, bytes: 1, risk: .review, evidence: [], identity: identity, source: .application, lastAccessDate: nil, isActive: false)
    let attempted = try await inactive.moveToQuarantine(candidate: candidate, destination: URL(fileURLWithPath: destination), planID: plan)
    require(!attempted, "no session means no helper request, not automatic elevation after permission failure")
    let missingIdentity = try HelperSigningIdentity(applicationIdentifier: "org.contract.missing." + UUID().uuidString, teamIdentifier: "A1B2C3D4E5")
    let missingClient = XPCPrivilegedHelperClient(identity: missingIdentity)
    let began = Date()
    do { _ = try await missingClient.ping(); require(false, "unregistered Mach service reported an authenticated connection") } catch { }
    require(Date().timeIntervalSince(began) < 8, "unavailable XPC connection must terminate through a bounded failure path")
    let cancelledPing = Task { try await missingClient.ping() }
    cancelledPing.cancel()
    do { _ = try await cancelledPing.value; require(false, "cancelled/unavailable XPC ping succeeded") } catch { }
    require(manager.fileExists(atPath: sentinel), "native unavailable/cancelled XPC checks must not mutate any fixture or register a daemon")
    print("PASS: helper peer requirements, explicit authorization, uid/path/plan/identity checks, no-follow move/restore/purge and budgets")
}

private struct NeverCalledHelperClient: PrivilegedHelperClient {
    func perform(_ request: HelperRequest) async throws -> HelperResponse { require(false, "helper was called without a session"); throw HelperClientError.notAuthorized }
}

func runPackagedHelperIdentityContract(binary: String, expectedExit: Int32) async throws {
    let output = try await BoundedProcess.run(binary, arguments: ["--self-check"], timeout: 5)
    require(output.status == expectedExit, "packaged Helper identity gate returned \(output.status), expected \(expectedExit)")
    print("PASS: packaged helper identity gate (no registration, daemon listener or privilege prompt)")
}
