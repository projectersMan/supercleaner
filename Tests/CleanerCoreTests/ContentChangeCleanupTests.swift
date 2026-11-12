import XCTest
@testable import CleanerCore

final class ContentChangeCleanupTests: XCTestCase {
    func testApprovedScopesAcceptWritesAndRemainRecoverable() async throws {
        let scopes: [(CandidateSource, CleanupCategory)] = [
            (.general, .cache), (.general, .log), (.general, .temporaryFile),
            (.general, .installerArtifact), (.general, .developerCache),
            (.projectArtifacts, .developerCache), (.diskAnalysis, .largeFile),
            (.application, .application), (.application, .applicationSupport),
            (.historicalApplicationResidue, .applicationSupport),
            (.agentWorkspace, .agentModelCache), (.agentWorkspace, .agentPackageCache)
        ]
        for (source, category) in scopes {
            for directory in [false, true] where category != .application || directory {
                let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
                defer { try? FileManager.default.removeItem(at: home) }
                let url = home.appendingPathComponent(category == .application ? "Applications/Test.app" : "Downloads/item")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if directory { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
                else { try Data("old".utf8).write(to: url) }
                let fs = LocalFileSystem()
                let identity = try await fs.identity(at: url)
                let candidate = CleanupCandidate(url: url, displayName: "item", category: category, bytes: identity.size,
                    risk: .review, evidence: [], identity: identity, source: source, lastAccessDate: nil, isActive: false)
                let plan = try PlanBuilder().build(candidates: [candidate], selectedIDs: [candidate.id])
                let payload = directory ? url.appendingPathComponent("new-content") : url
                try Data("updated content".utf8).write(to: payload)
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: url.path)
                let current = try await fs.identity(at: url)
                XCTAssertNotEqual(current, identity)
                let executor = CleanupExecutor(fileSystem: fs, pathPolicy: .init(homeDirectory: home),
                    quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: plan.ruleVersion)
                let receipt = await executor.execute(plan: plan)
                XCTAssertEqual(receipt.results.first?.status, .succeeded, "\(source)/\(category)/\(directory): \(receipt)")
                if !directory { XCTAssertEqual(receipt.results.first?.bytes, current.size) }
                let recovered = await executor.recoverInterruptedExecution(.init(id: receipt.id, plan: plan,
                    startedAt: receipt.startedAt, retentionPolicy: .hours24))
                XCTAssertEqual(recovered.results.first?.status, .succeeded)
                let restored = await executor.restore(receipt: receipt)
                XCTAssertEqual(restored.results.first?.status, .restored)
                XCTAssertEqual(try Data(contentsOf: payload), Data("updated content".utf8))
                let replacement = FileIdentity(device: identity.device, inode: identity.inode + 1,
                    size: identity.size, modificationTime: identity.modificationTime, kind: identity.kind)
                XCTAssertFalse(candidate.matchesExecutionIdentity(replacement))
                let link = FileIdentity(device: identity.device, inode: identity.inode,
                    size: identity.size, modificationTime: identity.modificationTime, kind: .symbolicLink)
                XCTAssertFalse(candidate.matchesExecutionIdentity(link))
            }
        }
    }

    func testHistoricalResidueValidatorAllowsContentUpdates() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appendingPathComponent("Library/Caches/test.removed-app")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: url)
        let identity = try await LocalFileSystem().identity(at: url)
        let candidate = CleanupCandidate(url: url, displayName: "residue", category: .cache, bytes: identity.size,
            risk: .review, evidence: [.init(code: "residue-bundle-id", summary: "test.removed-app")],
            identity: identity, source: .historicalApplicationResidue, lastAccessDate: nil, isActive: false)
        try Data("updated residue".utf8).write(to: url)
        let validator = HistoricalResidueExecutionValidator()
        // This test exercises file identity changes, not the host's installed apps or permissions.
        let inventory = ApplicationInventory(applications: [], coverage: CoverageSummary(), scannedAt: Date())
        try await validator.validate(candidate, context: .init(homeDirectory: home), inventory: inventory)
        try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("old"))
        try Data("replacement".utf8).write(to: url)
        do {
            try await validator.validate(candidate, context: .init(homeDirectory: home), inventory: inventory)
            XCTFail("A replacement must not inherit the old selection")
        } catch HistoricalResidueExecutionRejection.identityChanged { }
    }

    func testNonCacheAgentContentStillRequiresUnchangedSnapshot() {
        for category: CleanupCategory in [.agentSkill, .agentMCP, .agentSession, .agentSandbox, .agentWorktree, .agentUnknown, .credential, .configuration, .userKnowledge] {
            let identity = FileIdentity(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .file)
            let candidate = CleanupCandidate(url: URL(fileURLWithPath: "/tmp/agent"), displayName: "agent",
                category: category, bytes: 3, risk: .review, evidence: [], identity: identity,
                source: .agentWorkspace, lastAccessDate: nil, isActive: false)
            XCTAssertFalse(candidate.matchesExecutionIdentity(.init(device: 1, inode: 2, size: 5, modificationTime: 6, kind: .file)))
        }
    }

    func testHelperMoveAllowsWritesButRejectsReplacement() async {
        let operation = HelperOperation.moveToQuarantine(path: "/Applications/Test.app", destination: "/tmp/Test.app")
        let identity = FileIdentity(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .directory)
        let authorizer = HelperAuthorizer(expectedCallerRequirement: "test")
        let token = CapabilityToken.issueForTesting(operation: operation, identity: identity,
            callerRequirement: "test", expiresAt: Date().addingTimeInterval(60))
        let replaced = await authorizer.authorize(operation: operation, token: token,
            currentIdentity: .init(device: 1, inode: 9, size: 3, modificationTime: 4, kind: .directory))
        XCTAssertEqual(replaced, .rejected(.identityMismatch))
        let updated = await authorizer.authorize(operation: operation, token: token,
            currentIdentity: .init(device: 1, inode: 2, size: 8, modificationTime: 9, kind: .directory))
        XCTAssertEqual(updated, .accepted)
    }
}
