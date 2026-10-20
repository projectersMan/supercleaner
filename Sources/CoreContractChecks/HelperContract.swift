import CleanerCore
import Foundation

func runHelperContracts() async {
    let identity = FileIdentity(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .directory)
    let allowed = HelperOperation.moveToQuarantine(path: "/Library/Caches/example", destination: "/Library/Application Support/SuperCleaner/Quarantine/example")
    let token = CapabilityToken.issueForTesting(operation: allowed, identity: identity, callerRequirement: "anchor apple generic", expiresAt: Date(timeIntervalSince1970: 200))
    let authorizer = HelperAuthorizer(expectedCallerRequirement: "anchor apple generic")

    let wrong = await authorizer.authorize(operation: .moveToQuarantine(path: "/Library/Caches/other", destination: "/Library/Application Support/SuperCleaner/Quarantine/example"), token: token, currentIdentity: identity, now: Date(timeIntervalSince1970: 100))
    require(wrong == .rejected(.operationMismatch), "token authorized a different path")
    let accepted = await authorizer.authorize(operation: allowed, token: token, currentIdentity: identity, now: Date(timeIntervalSince1970: 100))
    require(accepted == .accepted, "matching capability token was rejected")
    let replay = await authorizer.authorize(operation: allowed, token: token, currentIdentity: identity, now: Date(timeIntervalSince1970: 100))
    require(replay == .rejected(.replayedNonce), "capability nonce was replayable")
}
