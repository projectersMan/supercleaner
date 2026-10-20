import Foundation

public struct ExecutionProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int
    public let currentURL: URL?

    public init(completed: Int, total: Int, currentURL: URL?) {
        self.completed = completed
        self.total = total
        self.currentURL = currentURL
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
        privilegedApplications: (any PrivilegedApplicationOperations)? = nil,
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
                reason: "清理计划已过期，请重新扫描"
            )
        }
        let liveVersion: String
        do { liveVersion = try await loadRuleVersion?() ?? currentRuleVersion }
        catch { return rejected(plan: plan, receiptID: receiptID, startedAt: startedAt, reason: "无法验证当前清理规则") }
        if plan.ruleVersion != liveVersion {
            return rejected(
                plan: plan,
                receiptID: receiptID,
                startedAt: startedAt,
                reason: "清理规则版本已变化，请重新扫描"
            )
        }

        let selected = plan.selectedItems
        var results: [OperationResult] = []
        var stoppedByCancellation = false
        var quarantineDirectoryCreated = false
        let planDirectory = quarantineRoot.appendingPathComponent(plan.id.uuidString, isDirectory: true)

        for (index, item) in selected.enumerated() {
            if Task.isCancelled { stoppedByCancellation = true; break }
            let candidate = item.candidate
            if plan.isExpired(at: now()) {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: "计划执行期间已过期，请重新扫描"))
                continue
            }
            progress(ExecutionProgress(completed: index, total: selected.count, currentURL: candidate.url))

            do {
                try await loadProtection().validate(candidate.url)
                try await validateCandidate(candidate)
                if let loadRuleVersion, try await loadRuleVersion() != plan.ruleVersion {
                    results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: "清理规则已变化，请重新扫描"))
                    continue
                }
                if candidate.category == .application, candidate.source == .application {
                    _ = try pathPolicy.validateApplicationBundle(candidate.url)
                } else {
                    _ = try pathPolicy.validateCandidate(candidate.url)
                }
            } catch {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: "安全策略拒绝执行：\(error)"))
                continue
            }
            guard !plan.isExpired(at: now()) else {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: "计划在安全校验期间已过期，请重新扫描"))
                continue
            }

            let currentlyActive = await isActive(candidate.url)
            let activityBlocksExecution = candidate.source != .general
                && (candidate.isActive || currentlyActive)
            guard !activityBlocksExecution else {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedActive, message: "项目仍在使用"))
                continue
            }
            guard !plan.isExpired(at: now()) else {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: "计划在活跃状态校验期间已过期，请重新扫描"))
                continue
            }

            do {
                let currentIdentity = try await fileSystem.identity(at: candidate.url)
                guard currentIdentity == candidate.identity else {
                    results.append(result(for: candidate, disposition: .skipped, status: .skippedIdentityChanged, message: "文件身份已变化"))
                    continue
                }
            } catch {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedIdentityChanged, message: "无法重新验证文件身份"))
                continue
            }
            guard !plan.isExpired(at: now()) else {
                results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: "计划在文件身份校验期间已过期，请重新扫描"))
                continue
            }

            do {
                if !quarantineDirectoryCreated {
                    try await fileSystem.createDirectory(planDirectory)
                    quarantineDirectoryCreated = true
                }
                guard !plan.isExpired(at: now()) else {
                    results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: "计划在隔离目录准备期间已过期，请重新扫描"))
                    continue
                }
                let destination = uniqueDestination(for: candidate, in: planDirectory)
                let handled = try await privilegedApplications?.moveToQuarantine(candidate: candidate, destination: destination, planID: plan.id) ?? false
                if !handled {
                    guard !plan.isExpired(at: now()) else {
                        results.append(result(for: candidate, disposition: .skipped, status: .skippedProtected, message: "计划在权限操作回退前已过期，请重新扫描"))
                        continue
                    }
                    try await fileSystem.move(candidate.url, to: destination)
                }
                let destinationExists = await fileSystem.fileExists(destination)
                let sourceExists = await fileSystem.fileExists(candidate.url)
                let movedIdentity = try? await fileSystem.identity(at: destination)
                let verified = destinationExists && !sourceExists && movedIdentity == candidate.identity
                if verified {
                    results.append(OperationResult(candidateID: candidate.id, originalURL: candidate.url, destinationURL: destination, disposition: .quarantined, status: .succeeded, bytes: candidate.bytes))
                } else {
                    results.append(OperationResult(candidateID: candidate.id, originalURL: candidate.url, destinationURL: destination, disposition: .failed, status: .failed, bytes: candidate.bytes, message: "移动后身份验证失败，日志保留", verificationNotBefore: now().addingTimeInterval(150)))
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
                results.append(result(for: item.candidate, disposition: .skipped, status: .skippedCancelled, message: "用户停止了尚未开始的项目"))
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

            let matchesIdentity = (try? await fileSystem.identity(at: destination)) == candidate.identity
            if destinationExists, !sourceExists, matchesIdentity {
                results.append(OperationResult(
                    candidateID: candidate.id,
                    originalURL: candidate.url,
                    destinationURL: destination,
                    disposition: .quarantined,
                    status: .succeeded,
                    bytes: candidate.bytes,
                    message: "启动时恢复了已完成的隔离操作"
                ))
            } else if sourceExists, !destinationExists {
                let mayBeInFlight = candidate.source == .application && candidate.url.path.hasPrefix("/Applications/")
                    && now() < entry.plan.expiresAt.addingTimeInterval(150) && previousReceipt == nil
                if mayBeInFlight {
                    results.append(OperationResult(candidateID: candidate.id, originalURL: candidate.url, destinationURL: destination,
                        disposition: .failed, status: .failed, bytes: candidate.bytes, message: "等待可能的在途 Helper 请求过期；日志保留",
                        verificationNotBefore: entry.plan.expiresAt.addingTimeInterval(150)))
                    continue
                }
                results.append(result(
                    for: candidate,
                    disposition: .skipped,
                    status: .skippedCancelled,
                    message: "应用退出前尚未执行"
                ))
            } else {
                results.append(OperationResult(
                    candidateID: candidate.id,
                    originalURL: candidate.url,
                    destinationURL: destinationExists ? destination : nil,
                    disposition: .failed,
                    status: .failed,
                    bytes: candidate.bytes,
                    message: destinationExists && !matchesIdentity ? "隔离路径存在但文件身份不匹配，禁止认定成功" : sourceExists
                        ? "原路径与隔离路径同时存在，无法判定执行结果"
                        : "原路径与隔离路径均不存在，无法判定执行结果",
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

    public func resolve(_ entry: ResolutionJournalEntry) async -> [OperationResult] {
        switch entry.action {
        case .restore:
            return await restore(entry: entry)
        case .trash:
            return await moveToTrash(entry: entry)
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
                restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: result.destinationURL, disposition: .skipped, status: .skippedProtected, bytes: result.bytes, message: "恢复源不属于本应用保留的已删除项目"))
                continue
            }
            let source = item.sourceURL
            guard let destination = item.destinationURL else {
                restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: source, disposition: .failed, status: .failed, bytes: result.bytes, message: "恢复日志缺少目标路径"))
                continue
            }
            let sourceExists = await fileSystem.fileExists(source)
            if !sourceExists {
                let destinationExists = await fileSystem.fileExists(destination)
                if item.sourceExistedAtPreparation, destinationExists {
                    let status: OperationStatus = destination == result.originalURL ? .restored : .restoreConflict
                    restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: destination, disposition: .restored, status: status, bytes: result.bytes, message: "启动时恢复了已完成的恢复操作"))
                } else {
                    restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: source, disposition: .failed, status: .failed, bytes: result.bytes, message: "保留的文件不存在"))
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
                restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: source, disposition: .skipped, status: .skippedProtected, bytes: result.bytes, message: "恢复目标不在安全边界内"))
                continue
            }
            do {
                let expectedIdentity = try await fileSystem.identity(at: source)
                let handled = try await privilegedApplications?.restore(source: source, destination: destination, planID: entry.receipt.planID) ?? false
                if !handled { try await fileSystem.move(source, to: destination) }
                guard !(await fileSystem.fileExists(source)), (try? await fileSystem.identity(at: destination)) == expectedIdentity else {
                    throw HelperMutationUncertain()
                }
                let hasConflict = destination != result.originalURL
                restored.append(OperationResult(candidateID: result.candidateID, originalURL: result.originalURL, destinationURL: destination, disposition: .restored, status: hasConflict ? .restoreConflict : .restored, bytes: result.bytes, message: hasConflict ? "原路径已有文件，已恢复到相邻路径" : nil))
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

    private func moveToTrash(entry: ResolutionJournalEntry) async -> [OperationResult] {
        var trashed: [OperationResult] = []
        let items = Dictionary(uniqueKeysWithValues: entry.items.map { ($0.candidateID, $0) })
        for result in entry.receipt.results where result.disposition == .quarantined {
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
                    message: "路径不属于本应用保留的已删除项目"
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
                        ? "启动时确认已移入系统废纸篓"
                        : "保留的文件在移动准备前已不存在，无法证明已移入系统废纸篓"
                ))
                continue
            }
            do {
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
                    message: "已移入系统废纸篓"
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
                    message: "路径不属于本应用保留的已删除项目"
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
                        message: "启动时确认已完成彻底删除"
                    ))
                } else {
                    deleted.append(OperationResult(
                        candidateID: result.candidateID,
                        originalURL: result.originalURL,
                        destinationURL: source,
                        disposition: .failed,
                        status: .sourceMissing,
                        bytes: result.bytes,
                        message: "保留的文件在删除准备前已不存在，无法证明彻底删除成功"
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
                    message: "已彻底删除"
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
