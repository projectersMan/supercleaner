import Foundation

public enum QuarantineRetentionPolicy: String, Codable, CaseIterable, Hashable, Sendable {
    case immediate
    case hours24
    case days2
    case days3
    case week1
    case month1
    case manual

    public func deadline(from date: Date) -> Date? {
        switch self {
        case .immediate: date
        case .hours24: date.addingTimeInterval(86_400)
        case .days2: date.addingTimeInterval(2 * 86_400)
        case .days3: date.addingTimeInterval(3 * 86_400)
        case .week1: date.addingTimeInterval(7 * 86_400)
        case .month1: Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: date)
        case .manual: nil
        }
    }

    public var displayTitle: String {
        switch self {
        case .immediate: "立即删除"
        case .hours24: "24 小时后"
        case .days2: "2 天后"
        case .days3: "3 天后"
        case .week1: "1 周后"
        case .month1: "1 个月后"
        case .manual: "手动保留"
        }
    }
}

public enum QuarantineCountdownState: Equatable, Sendable {
    case manual
    case scheduled
    case due
}

public struct QuarantineCountdown: Equatable, Sendable {
    public let state: QuarantineCountdownState
    public let remainingSeconds: TimeInterval

    public init(schedule: QuarantineSchedule, now: Date) {
        guard let deadline = schedule.scheduledDeletionAt else {
            state = .manual
            remainingSeconds = 0
            return
        }
        remainingSeconds = max(0, deadline.timeIntervalSince(now))
        state = deadline <= now ? .due : .scheduled
    }
}

public struct AutomaticCleanupFailureReason: Codable, Equatable, Hashable, Sendable {
    public enum Code: String, Codable, Equatable, Hashable, Sendable {
        case itemDeletionFailed
        case historyPersistenceFailed
    }

    public let code: Code
    public let message: String
    public let failedItemCount: Int

    public init(code: Code, message: String, failedItemCount: Int) {
        self.code = code
        self.message = message
        self.failedItemCount = failedItemCount
    }
}

public struct QuarantineSchedule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { receiptID }
    public let receiptID: UUID
    public let policy: QuarantineRetentionPolicy
    public let scheduledAt: Date
    public let scheduledDeletionAt: Date?
    public let lastAttemptAt: Date?
    public let failureReason: AutomaticCleanupFailureReason?
    public var failureMessage: String? { failureReason?.message }

    public init(
        receiptID: UUID,
        policy: QuarantineRetentionPolicy,
        scheduledAt: Date,
        scheduledDeletionAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        failureReason: AutomaticCleanupFailureReason? = nil
    ) {
        self.receiptID = receiptID
        self.policy = policy
        self.scheduledAt = scheduledAt
        self.scheduledDeletionAt = scheduledDeletionAt ?? policy.deadline(from: scheduledAt)
        self.lastAttemptAt = lastAttemptAt
        self.failureReason = failureReason
    }

    public func rescheduled(policy: QuarantineRetentionPolicy, at date: Date) -> QuarantineSchedule {
        QuarantineSchedule(receiptID: receiptID, policy: policy, scheduledAt: date)
    }

    public func recordingAttempt(
        at date: Date,
        failureReason: AutomaticCleanupFailureReason?
    ) -> QuarantineSchedule {
        QuarantineSchedule(
            receiptID: receiptID,
            policy: policy,
            scheduledAt: scheduledAt,
            scheduledDeletionAt: scheduledDeletionAt,
            lastAttemptAt: date,
            failureReason: failureReason
        )
    }
}

public actor QuarantineScheduleStore {
    private let url: URL
    private let manager: FileManager

    public init(url: URL, manager: FileManager = .default) {
        self.url = url
        self.manager = manager
    }

    public func schedules() throws -> [QuarantineSchedule] {
        guard manager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([QuarantineSchedule].self, from: Data(contentsOf: url))
    }

    public func schedule(receiptID: UUID) throws -> QuarantineSchedule? {
        try schedules().first { $0.receiptID == receiptID }
    }

    public func upsert(_ schedule: QuarantineSchedule) throws {
        var all = try schedules()
        if let index = all.firstIndex(where: { $0.receiptID == schedule.receiptID }) {
            all[index] = schedule
        } else {
            all.append(schedule)
        }
        try commit(all)
    }

    public func remove(receiptID: UUID) throws {
        let all = try schedules()
        let remaining = all.filter { $0.receiptID != receiptID }
        guard remaining.count != all.count else { return }
        try commit(remaining)
    }

    public func dueSchedules(
        at date: Date,
        retryInterval: TimeInterval = 3_600
    ) throws -> [QuarantineSchedule] {
        try schedules()
            .filter { schedule in
                guard let deadline = schedule.scheduledDeletionAt, deadline <= date else { return false }
                guard let lastAttemptAt = schedule.lastAttemptAt else { return true }
                return date.timeIntervalSince(lastAttemptAt) >= retryInterval
            }
            .sorted { ($0.scheduledDeletionAt ?? .distantFuture) < ($1.scheduledDeletionAt ?? .distantFuture) }
    }

    private func commit(_ schedules: [QuarantineSchedule]) throws {
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(schedules.sorted { $0.scheduledAt < $1.scheduledAt })
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".quarantine-schedules-\(UUID().uuidString).tmp")
        try data.write(to: temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()
        if manager.fileExists(atPath: url.path) {
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } else {
            try manager.moveItem(at: temporary, to: url)
        }
    }
}
