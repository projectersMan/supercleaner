import Foundation

private struct PreparedValidationRefusal: Error, Sendable, CustomStringConvertible {
    let message: String
    var description: String { message }
}

public struct ExecutionProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case processing, savingResults, movingToTrash }
    public let completed: Int
    public let total: Int
    public let currentURL: URL?
    public let result: OperationResult?
    public let phase: Phase

    public init(completed: Int, total: Int, currentURL: URL?, result: OperationResult? = nil, phase: Phase = .processing) {
        self.completed = completed
        self.total = total
        self.currentURL = currentURL
        self.result = result
        self.phase = phase
    }
}

public enum CleanupCandidateValidation: Sendable, Equatable {
    case valid
    case refused(String)
}

/// Immutable validation results prepared for one execution batch. The state
/// verifier remains live so a rule update still stops later mutations.
public struct CleanupValidationBatch: Sendable {
    public let ruleVersion: String
    public let results: [UUID: CleanupCandidateValidation]
    private let verifyRuleState: @Sendable () async throws -> Void

    public init(
        ruleVersion: String,
        results: [UUID: CleanupCandidateValidation],
        verifyRuleState: @escaping @Sendable () async throws -> Void
    ) {
        self.ruleVersion = ruleVersion
        self.results = results
        self.verifyRuleState = verifyRuleState
    }

    public func verifyCurrentRuleState() async throws {
        try await verifyRuleState()
    }
}

public actor CleanupExecutor {
    public typealias ProgressHandler = @Sendable (ExecutionProgress) -> Void
    private let fileSystem: any FileSystemAccess
    private let pathPolicy: PathPolicy
    private let quarantineRoot: URL
    private let currentRuleVersion: String
    private let now: @Sendable () -> Date
    private let isActive: @Sendable (URL) async -> Bool
    private let permanentRemove: @Sendable (URL) async throws -> Void
    private let loadProtection: @Sendable () async throws -> ProtectionPolicy
    private let loadRuleVersion: (@Sendable () async throws -> String)?
    private let validateCandidate: @Sendable (CleanupCandidate) async throws -> Void
    private let finalCandidateCheck: (@Sendable (CleanupCandidate) async throws -> Void)?
    private let applicationValidationTimeout: TimeInterval
    private let prepareValidationBatch: (@Sendable ([CleanupCandidate]) async throws -> CleanupValidationBatch)?
    private let privilegedApplications: (any PrivilegedApplicationOperations)?

    public init(
        fileSystem: any FileSystemAccess = LocalFileSystem(),
        pathPolicy: PathPolicy = PathPolicy(),
        quarantineRoot: URL,
        currentRuleVersion: String,
        now: @escaping @Sendable () -> Date = Date.init,
        isActive: @escaping @Sendable (URL) async -> Bool = { _ in false },
        loadProtection: @escaping @Sendable () async throws -> ProtectionPolicy = { ProtectionPolicy() },
        loadRuleVersion: (@Sendable () async throws -> String)? = nil,
        validateCandidate: @escaping @Sendable (CleanupCandidate) async throws -> Void = { _ in },
        prepareValidationBatch: (@Sendable ([CleanupCandidate]) async throws -> CleanupValidationBatch)? = nil,
        privilegedApplications: (any PrivilegedApplicationOperations)? = nil,
        finalCandidateCheck: (@Sendable (CleanupCandidate) async throws -> Void)? = nil,
        applicationValidationTimeout: TimeInterval = 15,
        permanentRemove: @escaping @Sendable (URL) async throws -> Void = { url in
            try FileManager.default.removeItem(at: url)
        }
    ) {
        self.fileSystem = fileSystem
        self.pathPolicy = pathPolicy
        self.quarantineRoot = quarantineRoot
        self.currentRuleVersion = currentRuleVersion
        self.now = now
        self.isActive = isActive
        self.permanentRemove = permanentRemove
        self.loadProtection = loadProtection
        self.loadRuleVersion = loadRuleVersion
        self.validateCandidate = validateCandidate
        self.finalCandidateCheck = finalCandidateCheck
        self.applicationValidationTimeout = max(0.01, applicationValidationTimeout)
        self.prepareValidationBatch = prepareValidationBatch
        self.privilegedApplications = privilegedApplications
    }

    public func execute(plan: CleanupPlan, progress: ProgressHandler = { _ in }) async -> OperationReceipt {
        await execute(
            plan: plan,
            receiptID: UUID(),
            startedAt: now(),
            progress: progress
        )
    }

    public func execute(
        plan: CleanupPlan,
        receiptID: UUID,
        startedAt: Date,
        progress: ProgressHandler
    ) async -> OperationReceipt {
        if plan.isExpired(at: startedAt) {
            return rejected(
                plan: plan,
                receiptID: receiptID,
                startedAt: startedAt,
                reason: L10n.text("清理计划已过期，请重新扫描")
            )
        }
        let selected = plan.selectedItems
        guard !selected.contains(where: { $0.candidate.hasIncompleteScan }) else {
            return rejected(plan: plan, receiptID: receiptID, startedAt: startedAt,
                reason: L10n.text("未完成目录验证，不可删除"))
        }
        if LargeFileCleanupProof.conflictingCandidate(in: selected.map(\.candidate)) != nil {
            return rejected(plan: plan, receiptID: receiptID, startedAt: startedAt,
                reason: L10n.text("清理计划包含必须保留的文件或目录"))
        }
        let batchCandidates = selected.map(\.candidate).filter { candidate in
            candidate.source == .general || candidate.source == .historicalApplicationResidue
        }
        let validationBatch: CleanupValidationBatch?
        do {
            validationBatch = batchCandidates.isEmpty ? nil : try await prepareValidationBatch?(batchCandidates)
        } catch is CancellationError {
            return rejected(plan: plan, receiptID: receiptID, startedAt: startedAt, reason: L10n.text("用户停止了尚未开始的项目"))
        } catch {
            return rejected(plan: plan, receiptID: receiptID, startedAt: startedAt, reason: L10n.text("无法验证当前清理规则"))
        }
        if Task.isCancelled {
            return rejected(plan: plan, receiptID: receiptID, startedAt: startedAt, reason: L10n.text("用户停止了尚未开始的项目"))
        }
        let liveVersion: String
        do {
            if let validationBatch { liveVersion = validationBatch.ruleVersion }
            else { liveVersion = try await loadRuleVersion?() ?? currentRuleVersion }
        }
        catch { return rejected(plan: plan, receiptID: receiptID, startedAt: startedAt, reason: L10n.text("无法验证当前清理规则")) }
        if plan.ruleVersion != liveVersion {
            return rejected(
                plan: plan,
                receiptID: receiptID,
                startedAt: startedAt,
                reason: L10n.text("清理规则版本已变化，请重新扫描")
            )
        }

        var results: [OperationResult] = []
        var stoppedByCancellation = false
        var quarantineDirectoryCreated = false
        var checkedGeneralActivity = false
        let applicationValidationBudget = ApplicationValidationBudget(seconds: applicationValidationTimeout)
        let planDirectory = quarantineRoot.appendingPathComponent(plan.id.uuidString, isDirectory: true)

        for (index, item) in selected.enumerated() {
            if Task.isCancelled { stoppedByCancellation = true; break }
            let candidate = item.candidate
            let previousResultCount = results.count
            defer {
                if results.count > previousResultCount {
                    progress(ExecutionProgress(completed: results.count, total: selected.count, currentURL: nil, result: results.last))
                }
            }
            if plan.isExpired(at: now()) {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: L10n.text("计划执行期间已过期，请重新扫描")))
                continue
            }
            progress(ExecutionProgress(completed: index, total: selected.count, currentURL: candidate.url))
            if candidate.source == .application, candidate.category != .application,
               await applicationValidationBudget.associationBudgetExhausted {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected,
                    message: String(describing: ApplicationValidationDeadlineError.timedOut)))
                continue
            }

            do {
                let initialIdentity = try await fileSystem.identity(at: candidate.url)
                guard matchesExecutionIdentity(initialIdentity, candidate: candidate) else {
                    results.append(result(for: candidate, disposition: .skipped, status: .skippedIdentityChanged, message: L10n.text("文件身份已变化")))
                    continue
                }
            } catch FileSystemError.missing {
                results.append(result(for: candidate, disposition: .skipped, status: .sourceMissing, message: L10n.text("文件已不存在")))
                continue
            } catch {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedIdentityChanged, message: L10n.text("无法重新验证文件身份")))
                continue
            }

            do {
                try await loadProtection().validate(candidate.url)
                if let validationBatch, let prepared = validationBatch.results[candidate.id] {
                    try await validationBatch.verifyCurrentRuleState()
                    if case let .refused(message) = prepared { throw PreparedValidationRefusal(message: message) }
                } else {
                    if candidate.source == .application {
                        let validate = validateCandidate
                        try await applicationValidationBudget.validate(candidate) {
                            try await validate(candidate)
                        }
                    } else { try await validateCandidate(candidate) }
                    if let loadRuleVersion, try await loadRuleVersion() != plan.ruleVersion {
                        results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: L10n.text("清理规则已变化，请重新扫描")))
                        continue
                    }
                }
                if candidate.category == .application, candidate.source == .application {
                    _ = try pathPolicy.validateApplicationBundle(candidate.url)
                } else {
                    if candidate.category == .largeFile,
                       !LargeFileCleanupScope(homeDirectory: pathPolicy.homeDirectory).allows(candidate.url, forManualSelection: true) {
                        throw PathPolicyError.protectedPath(candidate.url.path)
                    }
                    _ = try pathPolicy.validateCandidate(candidate.url)
                }
            } catch {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: L10n.text("安全策略拒绝执行：{0}", String(describing: error))))
                continue
            }
            if Task.isCancelled { stoppedByCancellation = true; break }
            guard !plan.isExpired(at: now()) else {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: L10n.text("计划在安全校验期间已过期，请重新扫描")))
                continue
            }

            let currentlyActive: Bool
            if candidate.source == .general {
                if !checkedGeneralActivity {
                    _ = await isActive(candidate.url)
                    checkedGeneralActivity = true
                }
                currentlyActive = false
            } else {
                currentlyActive = await isActive(candidate.url)
            }
            let activityBlocksExecution = candidate.source != .general
                && (candidate.isActive || currentlyActive)
            guard !activityBlocksExecution else {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedActive, message: L10n.text("项目仍在使用")))
                continue
            }
            guard !plan.isExpired(at: now()) else {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: L10n.text("计划在活跃状态校验期间已过期，请重新扫描")))
                continue
            }

            do {
                let currentIdentity = try await fileSystem.identity(at: candidate.url)
                guard matchesExecutionIdentity(currentIdentity, candidate: candidate) else {
                    results.append(result(for: candidate, disposition: .skipped, status: .skippedIdentityChanged, message: L10n.text("文件身份已变化")))
                    continue
                }
            } catch {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedIdentityChanged, message: L10n.text("无法重新验证文件身份")))
                continue
            }
            guard !plan.isExpired(at: now()) else {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: L10n.text("计划在文件身份校验期间已过期，请重新扫描")))
                continue
            }

            if Task.isCancelled { stoppedByCancellation = true; break }
            do {
                if !quarantineDirectoryCreated {
                    try await fileSystem.createDirectory(planDirectory)
                    quarantineDirectoryCreated = true
                }
                guard !plan.isExpired(at: now()) else {
                    results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: L10n.text("计划在隔离目录准备期间已过期，请重新扫描")))
                    continue
                }
                let destination = uniqueDestination(for: candidate, in: planDirectory)
                let handled = try await privilegedApplications?.moveToQuarantine(candidate: candidate, destination: destination, planID: plan.id) ?? false
                if !handled {
                    guard !plan.isExpired(at: now()) else {
                        results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: L10n.text("计划在权限操作回退前已过期，请重新扫描")))
                        continue
                    }
                    if allowsContentChanges(candidate) {
                        if candidate.identity.kind == .directory {
                            do {
                                let check = finalCandidateCheck ?? validateCandidate
                                if candidate.source == .application {
                                    try await applicationValidationBudget.validate(candidate) { try await check(candidate) }
                                } else { try await check(candidate) }
                                if let validationBatch { try await validationBatch.verifyCurrentRuleState() }
                                else if let loadRuleVersion, try await loadRuleVersion() != plan.ruleVersion {
                                    throw RuleScanError.executionRefused(candidate.ruleID ?? "changed-rules")
                                }
                            }
                            catch {
                                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected,
                                    message: L10n.text("安全策略拒绝执行：{0}", String(describing: error))))
                                continue
                            }
                        }
                        // Preparation/fallback can suspend. Recheck immediately
                        // before moving; rotation is not a content-only change.
                        guard let current = try? await fileSystem.identity(at: candidate.url),
                              matchesExecutionIdentity(current, candidate: candidate) else {
                            results.append(result(for: candidate, disposition: .skipped, status: .skippedIdentityChanged, message: L10n.text("文件身份已变化")))
                            continue
                        }
                    }
                    if let proof = candidate.largeFileProof, !proof.isCurrent(for: candidate) {
                        results.append(result(for: candidate, disposition: .skipped, status: .skippedIdentityChanged,
                            message: L10n.text("副本或保留内容已变化，请刷新重复大文件")))
                        continue
                    }
                    if Task.isCancelled { stoppedByCancellation = true; break }
                    guard !plan.isExpired(at: now()) else {
                        results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected,
                            message: L10n.text("计划在文件身份校验期间已过期，请重新扫描")))
                        continue
                    }
                    try await fileSystem.move(candidate.url, to: destination)
                }
                if let movedIdentity = await verifiedQuarantinedIdentity(candidate: candidate, destination: destination) {
                    results.append(OperationResult(candidateID: candidate.id, originalURL: candidate.url, destinationURL: destination, disposition: .quarantined, status: .succeeded, bytes: allowsContentChanges(candidate) && movedIdentity.kind == .file ? movedIdentity.size : candidate.bytes))
                } else {
                    results.append(OperationResult(candidateID: candidate.id, originalURL: candidate.url, destinationURL: destination, disposition: .failed, status: .failed, bytes: candidate.bytes, message: L10n.text("移动后身份验证失败，日志保留"), verificationNotBefore: now().addingTimeInterval(150)))
                }
            } catch {
                if error is HelperMutationUncertain {
                    results.append(OperationResult(candidateID: candidate.id, originalURL: candidate.url,
                        destinationURL: uniqueDestination(for: candidate, in: planDirectory), disposition: .failed, status: .failed,
                        bytes: candidate.bytes, message: error.localizedDescription, verificationNotBefore: now().addingTimeInterval(150)))
                } else {
                    results.append(result(for: candidate, disposition: .failed, status: .failed, message: String(describing: error)))
                }
            }
        }

        if stoppedByCancellation {
            let completedIDs = Set(results.map(\.candidateID))
            for item in selected where !completedIDs.contains(item.candidate.id) {
                results.append(result(for: item.candidate, disposition: .skipped, status: .skippedCancelled, message: L10n.text("用户停止了尚未开始的项目")))
            }
        }

        progress(ExecutionProgress(completed: results.count, total: selected.count, currentURL: nil))
        let status: OperationReceipt.OverallStatus
        if results.isEmpty, !selected.isEmpty { status = .failed }
        else if stoppedByCancellation { status = .partial }
        else if results.allSatisfy({ $0.status == .succeeded }) { status = .completed }
        else { status = .partial }
        return OperationReceipt(
            id: receiptID,
            planID: plan.id,
            startedAt: startedAt,
            completedAt: now(),
            results: results,
            overallStatus: status
        )
    }

    public func recoverInterruptedExecution(_ entry: ExecutionJournalEntry, previousReceipt: OperationReceipt? = nil) async -> OperationReceipt {
        let planDirectory = quarantineRoot.appendingPathComponent(entry.plan.id.uuidString, isDirectory: true)
        var results: [OperationResult] = []

        for item in entry.plan.selectedItems {
            let candidate = item.candidate
            if let previous = previousReceipt?.results.first(where: { $0.candidateID == candidate.id }) {
                guard let notBefore = previous.verificationNotBefore else { results.append(previous); continue }
                if now() < notBefore { results.append(previous); continue }
            }
            let destination = uniqueDestination(for: candidate, in: planDirectory)
            let sourceExists = await fileSystem.fileExists(candidate.url)
            let destinationExists = await fileSystem.fileExists(destination)

            let movedIdentity = await verifiedQuarantinedIdentity(candidate: candidate, destination: destination)
            let matchesIdentity = movedIdentity != nil
            if let movedIdentity {
                results.append(OperationResult(
                    candidateID: candidate.id,
                    originalURL: candidate.url,
                    destinationURL: destination,
                    disposition: .quarantined,
                    status: .succeeded,
                    bytes: allowsContentChanges(candidate) && movedIdentity.kind == .file ? movedIdentity.size : candidate.bytes,
                    message: L10n.text("启动时恢复了已完成的隔离操作")
                ))
            } else if sourceExists, !destinationExists {
                let mayBeInFlight = candidate.source == .application && candidate.url.path.hasPrefix("/Applications/")
                    && now() < entry.plan.expiresAt.addingTimeInterval(150) && previousReceipt == nil
                if mayBeInFlight {
                    results.append(OperationResult(candidateID: candidate.id, originalURL: candidate.url, destinationURL: destination,
                        disposition: .failed, status: .failed, bytes: candidate.bytes, message: L10n.text("等待可能的在途 Helper 请求过期；日志保留"),
                        verificationNotBefore: entry.plan.expiresAt.addingTimeInterval(150)))
                    continue
                }
                results.append(result(
                    for: candidate,
                    disposition: .skipped,
                    status: .skippedCancelled,
                    message: L10n.text("应用退出前尚未执行")
                ))
            } else {
                results.append(OperationResult(
                    candidateID: candidate.id,
                    originalURL: candidate.url,
                    destinationURL: destinationExists ? destination : nil,
                    disposition: .failed,
                    status: .failed,
                    bytes: candidate.bytes,
                    message: destinationExists && !matchesIdentity ? L10n.text("隔离路径存在但文件身份不匹配，禁止认定成功") : sourceExists
                        ? L10n.text("原路径与隔离路径同时存在，无法判定执行结果")
                        : L10n.text("原路径与隔离路径均不存在，无法判定执行结果"),
                    verificationNotBefore: previousReceipt?.results.first(where: { $0.candidateID == candidate.id })?.verificationNotBefore != nil
                        || (candidate.source == .application && candidate.url.path.hasPrefix("/Applications/")) ? now().addingTimeInterval(60) : nil
                ))
            }
        }

        let status: OperationReceipt.OverallStatus
        if results.allSatisfy({ $0.status == .succeeded }) {
            status = .completed
        } else if results.contains(where: { $0.status == .succeeded }) {
            status = .partial
        } else {
            status = .failed
        }
        return OperationReceipt(
            id: entry.id,
            planID: entry.plan.id,
            startedAt: entry.startedAt,
            completedAt: now(),
            results: results,
            overallStatus: status
        )
    }

    public func prepareResolution(
        action: ResolutionAction,
        receipt: OperationReceipt,
        id: UUID,
        startedAt: Date
    ) async -> ResolutionJournalEntry {
        var items: [ResolutionJournalItem] = []
        for result in receipt.results where result.disposition == .quarantined {
            guard let sourceURL = result.destinationURL else { continue }
            let destinationURL: URL?
            switch action {
            case .restore:
                let hasConflict = await fileSystem.fileExists(result.originalURL)
                destinationURL = hasConflict
                    ? recoverySibling(for: result.originalURL, resolutionID: id)
                    : result.originalURL
            case .trash, .purge:
                destinationURL = nil
            }
            items.append(ResolutionJournalItem(
                candidateID: result.candidateID,
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                sourceExistedAtPreparation: await fileSystem.fileExists(sourceURL)
            ))
        }
        return ResolutionJournalEntry(
            id: id,
            action: action,
            receipt: receipt,
            startedAt: startedAt,
            items: items
        )
    }

    public func resolve(_ entry: ResolutionJournalEntry, progress: ProgressHandler = { _ in }) async -> [OperationResult] {
        if let completed = entry.cancellationResults { return completed }
        switch entry.action {
        case .restore:
            return await restore(entry: entry)
        case .trash:
            return await moveToTrash(entry: entry, progress: progress)
        case .purge:
            return await purge(entry: entry)
        }
    }

    public func restore(receipt: OperationReceipt) async -> RestoreReceipt {
        let id = UUID()
        let entry = await prepareResolution(
            action: .restore,
            receipt: receipt,
            id: id,
            startedAt: now()
        )
        let results = await resolve(entry)
        return RestoreReceipt(
            id: id,
            sourceReceiptID: receipt.id,
            completedAt: now(),
            results: results
        )
    }

    private func restore(entry: ResolutionJournalEntry) async -> [OperationResult] {
        var restored: [OperationResult] = []
        let items = Dictionary(uniqueKeysWithValues: entry.items.map { ($0.candidateID, $0) })
        for result in entry.receipt.results where result.disposition == .quarantined {
            guard let item = items[result.candidateID],
                  isOwnedQuarantineURL(item.sourceURL, receipt: entry.receipt, result: result)
            else {
                restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: result.destinationURL, disposition: .skipped, status: .skippedProtected, bytes: result.bytes, message: L10n.text("恢复源不属于本应用保留的已删除项目")))
                continue
            }
            let source = item.sourceURL
            guard let destination = item.destinationURL else {
                restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: source, disposition: .failed, status: .failed, bytes: result.bytes, message: L10n.text("恢复日志缺少目标路径")))
                continue
            }
            let sourceExists = await fileSystem.fileExists(source)
            if !sourceExists {
                let destinationExists = await fileSystem.fileExists(destination)
                if item.sourceExistedAtPreparation, destinationExists {
                    let status: OperationStatus = destination == result.originalURL ? .restored : .restoreConflict
                    restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: destination, disposition: .restored, status: status, bytes: result.bytes, message: L10n.text("启动时恢复了已完成的恢复操作")))
                } else {
                    restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: source, disposition: .failed, status: .failed, bytes: result.bytes, message: L10n.text("保留的文件不存在")))
                }
                continue
            }
            do {
                if result.originalURL.pathExtension.lowercased() == "app" {
                    _ = try pathPolicy.validateApplicationBundle(result.originalURL)
                } else {
                    _ = try pathPolicy.validateCandidate(result.originalURL)
                }
            } catch {
                restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: source, disposition: .skipped, status: .skippedProtected, bytes: result.bytes, message: L10n.text("恢复目标不在安全边界内")))
                continue
            }
            do {
                let expectedIdentity = try await fileSystem.identity(at: source)
                let handled = try await privilegedApplications?.restore(source: source, destination: destination, planID: entry.receipt.planID) ?? false
                if !handled { try await fileSystem.move(source, to: destination) }
                let restoredIdentity = try? await fileSystem.identity(at: destination)
                // Contents may change during restore. Verify that the same
                // file or directory object was moved.
                let matches = restoredIdentity.map { sameObject($0, expectedIdentity) } == true
                guard !(await fileSystem.fileExists(source)), matches else {
                    throw HelperMutationUncertain()
                }
                let hasConflict = destination != result.originalURL
                restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: destination, disposition: .restored, status: hasConflict ? .restoreConflict : .restored, bytes: result.bytes, message: hasConflict ? L10n.text("原路径已有文件，已恢复到相邻路径") : nil))
            } catch {
                restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: destination, disposition: .failed, status: .failed, bytes: result.bytes, message: String(describing: error)))
            }
        }
        return restored
    }

    public func purge(receipt: OperationReceipt) async -> PurgeReceipt {
        let id = UUID()
        let entry = await prepareResolution(
            action: .purge,
            receipt: receipt,
            id: id,
            startedAt: now()
        )
        let results = await resolve(entry)
        return PurgeReceipt(
            id: id,
            sourceReceiptID: receipt.id,
            completedAt: now(),
            results: results
        )
    }

    private func moveToTrash(entry: ResolutionJournalEntry, progress: ProgressHandler) async -> [OperationResult] {
        var trashed: [OperationResult] = []
        let items = Dictionary(uniqueKeysWithValues: entry.items.map { ($0.candidateID, $0) })
        let total = entry.receipt.results.filter { $0.disposition == .quarantined }.count
        for result in entry.receipt.results where result.disposition == .quarantined {
            if Task.isCancelled { break }
            progress(.init(completed: trashed.count, total: total, currentURL: result.originalURL, phase: .movingToTrash))
            defer { progress(.init(completed: trashed.count, total: total, currentURL: nil, phase: .movingToTrash)) }
            guard let item = items[result.candidateID],
                  isOwnedQuarantineURL(item.sourceURL, receipt: entry.receipt, result: result)
            else {
                trashed.append(OperationResult(
                    candidateID: result.candidateID,
                    originalURL: result.originalURL,
                    destinationURL: result.destinationURL,
                    disposition: .skipped,
                    status: .skippedProtected,
                    bytes: result.bytes,
                    message: L10n.text("路径不属于本应用保留的已删除项目")
                ))
                continue
            }
            let source = item.sourceURL
            guard await fileSystem.fileExists(source) else {
                trashed.append(OperationResult(
                    candidateID: result.candidateID,
                    originalURL: result.originalURL,
                    destinationURL: source,
                    disposition: item.sourceExistedAtPreparation ? .trashed : .failed,
                    status: item.sourceExistedAtPreparation ? .succeeded : .sourceMissing,
                    bytes: result.bytes,
                    message: item.sourceExistedAtPreparation
                        ? L10n.text("启动时确认已移入系统废纸篓")
                        : L10n.text("保留的文件在移动准备前已不存在，无法证明已移入系统废纸篓")
                ))
                continue
            }
            do {
                // Stop can arrive while publishing progress or checking the
                // source. Once macOS starts a move, finish and record that item.
                if Task.isCancelled { break }
                let trashURL = try await fileSystem.trash(source)
                guard !(await fileSystem.fileExists(source)) else {
                    throw FileSystemError.trashUnavailable(source)
                }
                trashed.append(OperationResult(
                    candidateID: result.candidateID,
                    originalURL: result.originalURL,
                    destinationURL: trashURL,
                    disposition: .trashed,
                    status: .succeeded,
                    bytes: result.bytes,
                    message: L10n.text("已移入系统废纸篓")
                ))
            } catch {
                trashed.append(OperationResult(
                    candidateID: result.candidateID,
                    originalURL: result.originalURL,
                    destinationURL: source,
                    disposition: .failed,
                    status: .failed,
                    bytes: result.bytes,
                    message: String(describing: error)
                ))
            }
        }
        return trashed
    }

    private func purge(entry: ResolutionJournalEntry) async -> [OperationResult] {
        var deleted: [OperationResult] = []
        let items = Dictionary(uniqueKeysWithValues: entry.items.map { ($0.candidateID, $0) })
        for result in entry.receipt.results where result.disposition == .quarantined {
            guard let item = items[result.candidateID],
                  isOwnedQuarantineURL(item.sourceURL, receipt: entry.receipt, result: result)
            else {
                deleted.append(OperationResult(
                    candidateID: result.candidateID,
                    originalURL: result.originalURL,
                    destinationURL: result.destinationURL,
                    disposition: .skipped,
                    status: .skippedProtected,
                    bytes: result.bytes,
                    message: L10n.text("路径不属于本应用保留的已删除项目")
                ))
                continue
            }
            let source = item.sourceURL
            guard await fileSystem.fileExists(source) else {
                if item.sourceExistedAtPreparation {
                    deleted.append(OperationResult(
                        candidateID: result.candidateID,
                        originalURL: result.originalURL,
                        destinationURL: source,
                        disposition: .permanentlyDeleted,
                        status: .succeeded,
                        bytes: result.bytes,
                        message: L10n.text("启动时确认已完成彻底删除")
                    ))
                } else {
                    deleted.append(OperationResult(
                        candidateID: result.candidateID,
                        originalURL: result.originalURL,
                        destinationURL: source,
                        disposition: .failed,
                        status: .sourceMissing,
                        bytes: result.bytes,
                        message: L10n.text("保留的文件在删除准备前已不存在，无法证明彻底删除成功")
                    ))
                }
                continue
            }
            do {
                let handled = try await privilegedApplications?.purge(source: source, planID: entry.receipt.planID) ?? false
                if !handled { try await permanentRemove(source) }
                guard !(await fileSystem.fileExists(source)) else {
                    throw FileSystemError.trashUnavailable(source)
                }
                deleted.append(OperationResult(
                    candidateID: result.candidateID,
                    originalURL: result.originalURL,
                    destinationURL: source,
                    disposition: .permanentlyDeleted,
                    status: .succeeded,
                    bytes: result.bytes,
                    message: L10n.text("已彻底删除")
                ))
            } catch {
                deleted.append(OperationResult(
                    candidateID: result.candidateID,
                    originalURL: result.originalURL,
                    destinationURL: source,
                    disposition: .failed,
                    status: .failed,
                    bytes: result.bytes,
                    message: String(describing: error)
                ))
            }
        }
        return deleted
    }

    private func rejected(
        plan: CleanupPlan,
        receiptID: UUID,
        startedAt: Date,
        reason: String
    ) -> OperationReceipt {
        OperationReceipt(
            id: receiptID,
            planID: plan.id,
            startedAt: startedAt,
            completedAt: now(),
            results: [],
            overallStatus: .rejected,
            rejectionReason: reason
        )
    }

    private func allowsContentChanges(_ candidate: CleanupCandidate) -> Bool {
        candidate.allowsExecutionContentChanges
    }

    private func sameObject(_ left: FileIdentity, _ right: FileIdentity) -> Bool {
        left.isSameObject(as: right)
    }

    private func matchesExecutionIdentity(_ current: FileIdentity, candidate: CleanupCandidate) -> Bool {
        candidate.matchesExecutionIdentity(current)
    }

    private func verifiedQuarantinedIdentity(candidate: CleanupCandidate, destination: URL) async -> FileIdentity? {
        guard await fileSystem.fileExists(destination),
              let moved = try? await fileSystem.identity(at: destination),
              matchesExecutionIdentity(moved, candidate: candidate) else { return nil }
        guard await fileSystem.fileExists(candidate.url) else { return moved }
        // A writer may recreate the original pathname after rename. Success
        // concerns the selected inode; preserve the newly created regular file.
        guard allowsContentChanges(candidate), let replacement = try? await fileSystem.identity(at: candidate.url),
              replacement.kind == candidate.identity.kind, !sameObject(replacement, candidate.identity) else { return nil }
        return moved
    }

    private func result(for candidate: CleanupCandidate, disposition: OperationDisposition, status: OperationStatus, message: String) -> OperationResult {
        OperationResult(candidateID: candidate.id, originalURL: candidate.url, disposition: disposition, status: status, bytes: candidate.bytes, message: message)
    }

    private func uniqueDestination(for candidate: CleanupCandidate, in directory: URL) -> URL {
        directory.appendingPathComponent(candidate.id.uuidString + "-" + candidate.url.lastPathComponent)
    }

    private func recoverySibling(for original: URL, resolutionID: UUID) -> URL {
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        let recoveredName = base + " (Recovered " + resolutionID.uuidString.prefix(8) + ")" + (ext.isEmpty ? "" : "." + ext)
        return original.deletingLastPathComponent().appendingPathComponent(recoveredName)
    }

    private func isOwnedQuarantineURL(
        _ url: URL,
        receipt: OperationReceipt,
        result: OperationResult
    ) -> Bool {
        let candidate = url.standardizedFileURL
        let planDirectory = quarantineRoot
            .appendingPathComponent(receipt.planID.uuidString, isDirectory: true)
            .standardizedFileURL
        return candidate.deletingLastPathComponent() == planDirectory
            && candidate.lastPathComponent.hasPrefix(result.candidateID.uuidString + "-")
    }
}
