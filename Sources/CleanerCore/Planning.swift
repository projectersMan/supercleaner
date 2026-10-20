import CryptoKit
import Foundation

public enum PlanBuilderError: Error, Equatable, Sendable {
    case unknownSelection(UUID)
    case blockedSelection(UUID)
    case duplicateCandidate(UUID)
    case invalidTimeToLive
    case protectedSelection(UUID)
}

public struct PlanBuilder: Sendable {
    public let engineVersion: String
    public let ruleVersion: String
    public let planTTL: TimeInterval
    public let operatingSystemVersion: String
    private let protectionPolicy: ProtectionPolicy

    public init(
        engineVersion: String = "1.0.0",
        ruleVersion: String = "bundled-1",
        planTTL: TimeInterval = 300,
        operatingSystemVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        protectionPolicy: ProtectionPolicy = ProtectionPolicy()
    ) {
        self.engineVersion = engineVersion
        self.ruleVersion = ruleVersion
        self.planTTL = planTTL
        self.operatingSystemVersion = operatingSystemVersion
        self.protectionPolicy = protectionPolicy
    }

    public func build(candidates: [CleanupCandidate], selectedIDs: Set<UUID>, now: Date = Date()) throws -> CleanupPlan {
        guard planTTL > 0 else { throw PlanBuilderError.invalidTimeToLive }
        var seen = Set<UUID>()
        for candidate in candidates where !seen.insert(candidate.id).inserted {
            throw PlanBuilderError.duplicateCandidate(candidate.id)
        }
        let knownIDs = Set(candidates.map(\.id))
        if let unknown = selectedIDs.first(where: { !knownIDs.contains($0) }) {
            throw PlanBuilderError.unknownSelection(unknown)
        }
        if let blocked = candidates.first(where: { selectedIDs.contains($0.id) && !$0.risk.isSelectable }) {
            throw PlanBuilderError.blockedSelection(blocked.id)
        }
        for candidate in candidates where selectedIDs.contains(candidate.id) {
            do { try protectionPolicy.validate(candidate.url) }
            catch { throw PlanBuilderError.protectedSelection(candidate.id) }
        }

        let items = candidates.map { candidate in
            PlanItem(
                candidate: candidate,
                isSelected: selectedIDs.contains(candidate.id),
                action: .quarantine,
                evidenceDigest: evidenceDigest(for: candidate)
            )
        }
        return CleanupPlan(
            createdAt: now,
            expiresAt: now.addingTimeInterval(planTTL),
            items: items,
            engineVersion: engineVersion,
            ruleVersion: ruleVersion,
            operatingSystemVersion: operatingSystemVersion
        )
    }

    private func evidenceDigest(for candidate: CleanupCandidate) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(candidate.evidence)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
