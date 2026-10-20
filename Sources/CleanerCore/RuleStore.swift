import CryptoKit
import Foundation

public struct CleanupRule: Codable, Hashable, Sendable {
    public enum Granularity: String, Codable, Sendable { case children, root, descendantFiles }
    public let ruleID: String
    public let category: CleanupCategory
    public let relativePaths: [String]
    public let minimumAgeDays: Int
    public let defaultRisk: RiskLevel
    public let ownershipEvidence: String?
    public let regenerationEvidence: String?
    public let defaultSelection: Bool?
    public let minimumOSVersion: String?
    public let maximumOSVersion: String?
    public let sourceKind: String?
    public let sourceReference: String?
    public let validatedAt: Date?
    public let testFixture: String?
    public let granularity: Granularity?
    public let fileExtensions: Set<String>?
    public let protectedRelativePaths: [String]?
    public let activeBundleIdentifiers: Set<String>?
    public let activeProcessNames: Set<String>?
    public let maximumDepth: Int?
    public let maximumEntries: Int?

    public init(
        ruleID: String, category: CleanupCategory, relativePaths: [String], minimumAgeDays: Int, defaultRisk: RiskLevel,
        ownershipEvidence: String? = nil, regenerationEvidence: String? = nil, defaultSelection: Bool? = nil,
        minimumOSVersion: String? = nil, maximumOSVersion: String? = nil, sourceKind: String? = nil,
        sourceReference: String? = nil, validatedAt: Date? = nil, testFixture: String? = nil,
        granularity: Granularity? = nil, fileExtensions: Set<String>? = nil,
        protectedRelativePaths: [String]? = nil, activeBundleIdentifiers: Set<String>? = nil,
        activeProcessNames: Set<String>? = nil, maximumDepth: Int? = nil, maximumEntries: Int? = nil
    ) {
        self.ruleID = ruleID
        self.category = category
        self.relativePaths = relativePaths
        self.minimumAgeDays = minimumAgeDays
        self.defaultRisk = defaultRisk
        self.ownershipEvidence = ownershipEvidence
        self.regenerationEvidence = regenerationEvidence
        self.defaultSelection = defaultSelection
        self.minimumOSVersion = minimumOSVersion
        self.maximumOSVersion = maximumOSVersion
        self.sourceKind = sourceKind
        self.sourceReference = sourceReference
        self.validatedAt = validatedAt
        self.testFixture = testFixture
        self.granularity = granularity
        self.fileExtensions = fileExtensions
        self.protectedRelativePaths = protectedRelativePaths
        self.activeBundleIdentifiers = activeBundleIdentifiers
        self.activeProcessNames = activeProcessNames
        self.maximumDepth = maximumDepth
        self.maximumEntries = maximumEntries
    }
}

public struct RulePack: Codable, Hashable, Sendable {
    public let version: String
    public let issuedAt: Date
    public let rules: [CleanupRule]
    public let revokedRuleIDs: Set<String>
    public let activationID: UUID?

    public init(version: String, issuedAt: Date, rules: [CleanupRule], revokedRuleIDs: Set<String>, activationID: UUID? = nil) {
        self.version = version
        self.issuedAt = issuedAt
        self.rules = rules
        self.revokedRuleIDs = revokedRuleIDs
        self.activationID = activationID
    }

    /// Content identity prevents a signed same-version replacement from leaving
    /// old plans valid. Arrays and sets are normalized before hashing.
    public var executionVersion: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let canonicalRules = rules.sorted { $0.ruleID < $1.ruleID }.map { rule -> String in
            let data = (try? encoder.encode(rule)) ?? Data()
            // JSON Set order is unspecified; canonicalize the entire JSON value.
            let object = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
            return RulePack.canonical(object)
        }
        let payload = RulePack.canonical(["version": version, "activation": activationID?.uuidString ?? "", "rules": canonicalRules, "revoked": revokedRuleIDs.sorted()])
        return version + ":" + SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonical(_ value: Any) -> String {
        if let object = value as? [String: Any] {
            return "{" + object.keys.sorted().map { "\(canonical($0)):\(canonical(object[$0]!))" }.joined(separator: ",") + "}"
        }
        if let array = value as? [Any] { return "[" + array.map(canonical).sorted().joined(separator: ",") + "]" }
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

public struct SignedRuleUpdate: Codable, Hashable, Sendable {
    public let packData: Data
    public let signature: Data
    public init(packData: Data, signature: Data) { self.packData = packData; self.signature = signature }
}

public enum RuleStoreError: Error, Equatable, Sendable, LocalizedError {
    case invalidPublicKey
    case invalidSignature
    case invalidSchema
    case noCurrentRules
    case noPreviousRules
    case downgrade
    case futureDated
    case invalidStorage
    case storageLimit
    case interruptedCommit
    public var errorDescription: String? {
        switch self {
        case .invalidPublicKey: L10n.text("规则签名公钥无效或尚未配置")
        case .invalidSignature: L10n.text("规则签名验证失败")
        case .invalidSchema: L10n.text("规则格式或安全约束无效")
        case .noCurrentRules: L10n.text("没有可用的已验证规则")
        case .noPreviousRules: L10n.text("没有可回滚的上一份规则")
        case .downgrade: L10n.text("规则比已见版本旧，或属于回滚后的旧包重放")
        case .futureDated: L10n.text("规则发布时间超出允许的时钟偏差")
        case .invalidStorage: L10n.text("规则存储不可读、损坏或发生路径替换")
        case .storageLimit: L10n.text("规则及撤销证据超过存储限制")
        case .interruptedCommit: L10n.text("规则提交未完成，已保留此前规则")
        }
    }
}

public actor RuleStore {
    private let directory: URL
    private let publicKeyData: Data
    private let bundledURL: URL?
    private let manager: FileManager
    private var currentURL: URL { directory.appendingPathComponent("current.json") }
    private var previousURL: URL { directory.appendingPathComponent("previous.json") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var initializedURL: URL { directory.appendingPathComponent("initialized-v1") }
    private var failCommit = false
    private var failAfterBaseline = false
    private struct State: Codable {
        var schemaVersion = 1
        var current: SignedRuleUpdate?
        var previous: SignedRuleUpdate?
        var hasPrevious = false
        var highWaterUpdate: SignedRuleUpdate?
        var revocationProofs: [SignedRuleUpdate] = []
        var activationID: UUID?
    }

    public init(directory: URL, publicKey: Data, bundledURL: URL? = nil, manager: FileManager = .default) {
        self.directory = directory
        self.publicKeyData = publicKey
        self.bundledURL = bundledURL
        self.manager = manager
    }

    public func loadBundled() throws -> RulePack {
        guard let bundledURL else { throw RuleStoreError.noCurrentRules }
        return try decodeAndValidate(read(bundledURL, maximumBytes: 1_048_576))
    }

    public func install(update: SignedRuleUpdate) throws {
        try Task.checkCancellation()
        let pack = try validateSigned(update)
        guard pack.issuedAt <= Date().addingTimeInterval(600) else { throw RuleStoreError.futureDated }
        var state = try loadState()
        let baseline = state
        let highWater = try state.highWaterUpdate.map(validateSigned)
        let bundled = try bundledURL.map { _ in try loadBundled() }
        let minimumDate = max(highWater?.issuedAt ?? .distantPast, bundled?.issuedAt ?? .distantPast)
        if pack.issuedAt < minimumDate { throw RuleStoreError.downgrade }
        if let highWater, pack.issuedAt == highWater.issuedAt {
            guard update == state.highWaterUpdate else { throw RuleStoreError.downgrade }
            // An explicit rollback must not be undone by replaying the feed.
            guard state.current == update else { throw RuleStoreError.downgrade }
            return
        }
        if let current = state.current { _ = try validateSigned(current) }
        let revocations = try effectiveRevocations(state)
        state.previous = state.current
        state.hasPrevious = state.current != nil || bundled != nil
        state.current = update
        state.highWaterUpdate = update
        state.activationID = UUID()
        if pack.revokedRuleIDs.isSuperset(of: revocations) {
            state.revocationProofs = pack.revokedRuleIDs.isEmpty ? [] : [update]
        } else if !pack.revokedRuleIDs.isEmpty {
            state.revocationProofs.append(update)
        }
        try commit(state, baseline: baseline)
    }

    public func rollback() throws {
        try Task.checkCancellation()
        var state = try loadState()
        let baseline = state
        guard state.hasPrevious else { throw RuleStoreError.noPreviousRules }
        if let previous = state.previous { _ = try validateSigned(previous) }
        else { _ = try loadBundled() }
        _ = try effectiveRevocations(state)
        // A single atomic file switches both slots. Anti-replay high water and
        // signed revocation evidence deliberately survive this user action.
        let old = state.current
        state.current = state.previous
        state.previous = old
        state.activationID = UUID()
        try commit(state, baseline: baseline)
    }

    public func currentVersion() throws -> String {
        try currentPack().version
    }

    public func currentPack() throws -> RulePack {
        let state = try loadState()
        let pack = try state.current.map(validateSigned) ?? loadBundled()
        return RulePack(version: pack.version, issuedAt: pack.issuedAt, rules: pack.rules,
                        revokedRuleIDs: try pack.revokedRuleIDs.union(effectiveRevocations(state)), activationID: state.activationID)
    }

    public func canRollback() throws -> Bool {
        let state = try loadState()
        guard state.hasPrevious else { return false }
        if let previous = state.previous { _ = try validateSigned(previous) }
        else { _ = try loadBundled() }
        return true
    }
    public func failNextCommitForTesting() { failCommit = true }
    public func failAfterBaselineForTesting() { failAfterBaseline = true }

    private func loadState() throws -> State {
        guard directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path else { throw RuleStoreError.invalidStorage }
        if try exists(stateURL) {
            guard let state = try? JSONDecoder().decode(State.self, from: read(stateURL, maximumBytes: 8_388_608)),
                  state.schemaVersion == 1, state.revocationProofs.count <= 64 else { throw RuleStoreError.invalidStorage }
            if let high = state.highWaterUpdate { _ = try validateSigned(high) }
            _ = try effectiveRevocations(state)
            return state
        }
        // Losing an initialized state cannot silently re-enable bundled rules.
        guard !(try exists(initializedURL)) else { throw RuleStoreError.invalidStorage }
        guard try exists(currentURL) else { return State() }
        let current = try JSONDecoder().decode(SignedRuleUpdate.self, from: read(currentURL, maximumBytes: 1_500_000))
        let currentPack = try validateSigned(current)
        var state = State(current: current, hasPrevious: bundledURL != nil, highWaterUpdate: current)
        if !currentPack.revokedRuleIDs.isEmpty { state.revocationProofs = [current] }
        if try exists(previousURL) {
            let previous = try JSONDecoder().decode(SignedRuleUpdate.self, from: read(previousURL, maximumBytes: 1_500_000))
            let previousPack = try validateSigned(previous)
            state.previous = previous; state.hasPrevious = true
            if previousPack.issuedAt > currentPack.issuedAt { state.highWaterUpdate = previous }
            if !previousPack.revokedRuleIDs.isEmpty { state.revocationProofs.append(previous) }
        }
        return state
    }

    private func effectiveRevocations(_ state: State) throws -> Set<String> {
        var revoked = Set<String>()
        if bundledURL != nil { revoked.formUnion(try loadBundled().revokedRuleIDs) }
        for proof in state.revocationProofs { revoked.formUnion(try validateSigned(proof).revokedRuleIDs) }
        if let high = state.highWaterUpdate { revoked.formUnion(try validateSigned(high).revokedRuleIDs) }
        return revoked
    }

    private func commit(_ state: State, baseline: State) throws {
        try Task.checkCancellation()
        guard state.revocationProofs.count <= 64 else { throw RuleStoreError.storageLimit }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= 8_388_608 else { throw RuleStoreError.storageLimit }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard directory.standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path,
              (try manager.attributesOfItem(atPath: directory.path)[.type]) as? FileAttributeType == .typeDirectory else { throw RuleStoreError.invalidStorage }
        for url in [stateURL, initializedURL] where try exists(url) {
            guard (try manager.attributesOfItem(atPath: url.path)[.type]) as? FileAttributeType == .typeRegular else { throw RuleStoreError.invalidStorage }
        }
        if failCommit { failCommit = false; throw RuleStoreError.interruptedCommit }
        // First persist an equivalent baseline. A failed initial update must
        // keep bundled/legacy rules usable, even if marker creation succeeded.
        if !(try exists(stateURL)) {
            let baselineData = try encoder.encode(baseline)
            guard baselineData.count <= 8_388_608 else { throw RuleStoreError.storageLimit }
            try baselineData.write(to: stateURL, options: .atomic)
        }
        if !(try exists(initializedURL)) { try Data("1".utf8).write(to: initializedURL, options: .atomic) }
        if failAfterBaseline { failAfterBaseline = false; throw RuleStoreError.interruptedCommit }
        try data.write(to: stateURL, options: .atomic)
    }

    private func exists(_ url: URL) throws -> Bool {
        do { _ = try manager.attributesOfItem(atPath: url.path); return true }
        catch {
            let error = error as NSError
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            if error.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code),
               underlying == nil || (underlying?.domain == NSPOSIXErrorDomain && underlying?.code == 2) { return false }
            throw RuleStoreError.invalidStorage
        }
    }
    private func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let before = try manager.attributesOfItem(atPath: url.path)
        guard before[.type] as? FileAttributeType == .typeRegular,
              ((before[.size] as? NSNumber)?.uint64Value ?? .max) <= UInt64(maximumBytes) else { throw RuleStoreError.invalidStorage }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        let after = try manager.attributesOfItem(atPath: url.path)
        guard data.count <= maximumBytes, before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber,
              before[.modificationDate] as? Date == after[.modificationDate] as? Date else { throw RuleStoreError.invalidStorage }
        return data
    }

    public func isRevoked(ruleID: String) throws -> Bool {
        try currentPack().revokedRuleIDs.contains(ruleID)
    }

    private func decodeAndValidate(_ data: Data) throws -> RulePack {
        guard data.count <= 1_048_576, let pack = try? JSONDecoder().decode(RulePack.self, from: data),
              !pack.version.isEmpty, pack.version.count <= 100, pack.rules.count <= 2_000,
              pack.revokedRuleIDs.count <= 4_000, pack.activationID == nil else {
            throw RuleStoreError.invalidSchema
        }
        let identifiers = pack.rules.map(\.ruleID)
        guard Set(identifiers).count == identifiers.count,
              pack.rules.allSatisfy({ rule in
                  !rule.ruleID.isEmpty && rule.minimumAgeDays >= 0 && !rule.relativePaths.isEmpty
                      && rule.relativePaths.allSatisfy(validRelativePath)
                      && (rule.protectedRelativePaths ?? []).allSatisfy(validRelativePath)
                      && (rule.maximumDepth.map { (1...32).contains($0) } ?? true)
                      && (rule.maximumEntries.map { (1...100_000).contains($0) } ?? true)
                      && (rule.defaultRisk != .safe || (rule.regenerationEvidence?.isEmpty == false
                          && rule.ownershipEvidence?.isEmpty == false && rule.sourceReference?.isEmpty == false))
              }) else {
            throw RuleStoreError.invalidSchema
        }
        return pack
    }

    private func validateSigned(_ update: SignedRuleUpdate) throws -> RulePack {
        guard update.packData.count <= 1_048_576, update.signature.count == 64 else { throw RuleStoreError.invalidSchema }
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else { throw RuleStoreError.invalidPublicKey }
        guard key.isValidSignature(update.signature, for: update.packData) else { throw RuleStoreError.invalidSignature }
        let pack = try decodeAndValidate(update.packData)
        guard pack.issuedAt <= Date().addingTimeInterval(600) else { throw RuleStoreError.futureDated }
        return pack
    }

    private func validRelativePath(_ path: String) -> Bool {
        !path.isEmpty && path != "." && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
            && !path.split(separator: "/").contains(".")
            && path.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}
