import CleanerCore
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("Contract failed: \(message)\n".utf8))
        exit(1)
    }
}

if CommandLine.arguments.dropFirst().first == "--check-installed-uninstall" {
    try await runInstalledUninstallReadOnlyCheck(paths: Array(CommandLine.arguments.dropFirst(2)))
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-rule-engine" {
    try await runRuleEngineContracts()
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-ownership" {
    try await runApplicationOwnershipContracts()
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-helper" {
    try await runHelperIntegrationContracts()
    try await runHelperExecutionContracts()
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-review-recovery" {
    try await runReviewRecoveryRegressionContracts()
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-review-coverage" {
    try await runReviewCompletenessRegressionContracts()
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-review-expiry" {
    try await runReviewExpiryRegressionContracts()
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-updates" {
    try await runUpdateTransportContracts()
    try await runRuleUpdateContracts()
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-sparkle-release", CommandLine.arguments.count == 3 {
    try await runSparkleSigningInteropContract(tool: CommandLine.arguments[2])
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-production-gate", CommandLine.arguments.count == 4 {
    try await runProductionSigningNegativeContract(application: CommandLine.arguments[2], script: CommandLine.arguments[3])
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-helper-identity", CommandLine.arguments.count == 4, let expected = Int32(CommandLine.arguments[3]) {
    try await runPackagedHelperIdentityContract(binary: CommandLine.arguments[2], expectedExit: expected)
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-cli", CommandLine.arguments.count == 3 {
    try await runReadOnlyCommandLineContracts(binary: CommandLine.arguments[2])
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--check-cli-config", CommandLine.arguments.count == 3 {
    try await runPackagedRuleConfigurationContract(binary: CommandLine.arguments[2])
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--validate-release-config", CommandLine.arguments.count >= 3 {
    do {
        let config = try JSONDecoder().decode(ReleaseConfiguration.self, from: UpdateFileContent.read(URL(fileURLWithPath: CommandLine.arguments[2]), maximumBytes: 65_536))
        try config.validate(requireComplete: CommandLine.arguments.contains("--complete"))
        print("PASS: public release configuration identity, sources and signing keys")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("FAIL: public release configuration is missing or invalid.\n".utf8))
        exit(1)
    }
}
if CommandLine.arguments.dropFirst().first == "--validate-application-release", CommandLine.arguments.count == 7 {
    do {
        let config = try JSONDecoder().decode(ReleaseConfiguration.self, from: UpdateFileContent.read(URL(fileURLWithPath: CommandLine.arguments[2]), maximumBytes: 65_536))
        let digest = try SignedApplicationRelease.validate(appcast: URL(fileURLWithPath: CommandLine.arguments[3]), archive: URL(fileURLWithPath: CommandLine.arguments[4]), configuration: config,
            expectedBuild: CommandLine.arguments[5], minimumOS: CommandLine.arguments[6])
        print("PASS: signed appcast and archive match configured public key, build, origin, OS and length; SHA256 \(digest)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("FAIL: signed application release rejected.\n".utf8)); exit(1)
    }
}

require(RiskLevel.safe.isSelectableByDefault, "safe candidates must be selected by default")
require(!RiskLevel.review.isSelectableByDefault, "review candidates must require confirmation")
require(!RiskLevel.blocked.isSelectable, "blocked candidates must never be selectable")

let identity = FileIdentity(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .directory)
let candidate = CleanupCandidate(
    url: URL(fileURLWithPath: "/tmp/cache", isDirectory: true),
    displayName: "Build cache",
    category: .developerCache,
    bytes: 3,
    risk: .safe,
    evidence: [Evidence(code: "old-cache", summary: "Unused for 30 days")],
    identity: identity,
    source: .general,
    lastAccessDate: nil,
    isActive: false
)
let encoded = try JSONEncoder().encode(candidate)
let decoded = try JSONDecoder().decode(CleanupCandidate.self, from: encoded)
require(decoded == candidate, "candidate round-trip")

let blocked = CleanupCandidate(
    url: URL(fileURLWithPath: "/tmp/protected"),
    displayName: "Protected",
    category: .userKnowledge,
    bytes: 1,
    risk: .blocked,
    evidence: [],
    identity: FileIdentity(device: 1, inode: 3, size: 1, modificationTime: 4, kind: .file),
    source: .agentWorkspace,
    lastAccessDate: nil,
    isActive: false
)
let plan = CleanupPlan(
    createdAt: Date(timeIntervalSince1970: 100),
    expiresAt: Date(timeIntervalSince1970: 400),
    items: [PlanItem(candidate: candidate), PlanItem(candidate: blocked)]
)
require(plan.selectedItems.map(\.candidate.id) == [candidate.id], "plan selection")
require(plan.blockedItems.map(\.candidate.id) == [blocked.id], "blocked partition")
let reviewDefault = PlanItem(candidate: CleanupCandidate(url: URL(fileURLWithPath: "/tmp/review"), displayName: "Review", category: .cache, bytes: 1, risk: .review, evidence: [], identity: FileIdentity(device: 1, inode: 4, size: 1, modificationTime: 3, kind: .file), source: .general, lastAccessDate: nil, isActive: false))
require(!reviewDefault.isSelected, "review candidates must require explicit opt-in")
require(!PlanItem(candidate: blocked, isSelected: true).isSelected, "blocked candidates cannot be forced into selection")

runReviewInteractionContracts()
runReviewFilterContracts()
runAppNavigationContracts()
runCleanupRecommendationContracts()
runDefaultCleanupPolicyContracts()
runCleanupSessionSummaryContracts()
runCleanupModeContracts()
try runPathPolicyContracts()
try await runScannerContracts()
try await runCachedFirmwareScannerContracts()
try await runAgentScannerContracts()
runAgentCleanupPresentationContracts()
runAgentSkillPresentationPerformanceContract()
try await runApplicationContracts()
try await runApplicationOwnershipContracts()
try await runUninstallResilienceContracts()
try await runPlanningExecutionContracts()
try await runStoreContracts()
try await runRuleEngineContracts()
try await runInstallerDiscoveryContracts()
try await runReadOnlyInterfaceContracts()
try await runProjectArtifactContracts()
await runHelperContracts()
try await runHelperIntegrationContracts()
try await runHelperExecutionContracts()
try await runReviewRecoveryRegressionContracts()
try await runReviewCompletenessRegressionContracts()
try await runReviewExpiryRegressionContracts()
try await runUpdateTransportContracts()
try await runRuleUpdateContracts()
await runPermissionContracts()
try runCommercialContracts()

print("Core contracts passed")
