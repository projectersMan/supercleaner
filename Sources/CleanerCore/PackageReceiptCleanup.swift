import CryptoKit
import Darwin
import Foundation
import OSLog

/// A receipt-specific capability, never a general permission to delete /var/db.
public struct PackageReceiptCleanupProof: Codable, Hashable, Sendable {
    public let packageID: String
    public let fingerprint: String
    public let applications: [URL]
    public var receiptURL: URL {
        URL(fileURLWithPath: "/private/var/db/receipts").appendingPathComponent(packageID + ".plist")
    }
}

struct PackageReceiptManifest: Sendable {
    let packageID: String
    let fingerprint: String
    let paths: [URL]

    func proof(selectedApplications: Set<URL>) -> PackageReceiptCleanupProof? {
        let apps = Set(paths.compactMap { path -> URL? in
            let components = path.pathComponents
            guard let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else { return nil }
            return URL(fileURLWithPath: NSString.path(withComponents: Array(components[...index]))).standardizedFileURL
        })
        guard !apps.isEmpty, apps.isSubset(of: selectedApplications), paths.allSatisfy({ path in
            // Only structural parents of the app and the app's own payload are covered.
            apps.contains { app in path == app || path.path.hasPrefix(app.path + "/") || app.path.hasPrefix(path.path == "/" ? "/" : path.path + "/") }
        }) else { return nil }
        return .init(packageID: packageID, fingerprint: fingerprint, applications: apps.sorted { $0.path < $1.path })
    }
}

struct PackageReceiptStore: Sendable {
    let root: URL
    let requireRootOwnership: Bool
    private let forgetCommand: @Sendable (String, TimeInterval) async throws -> Void
    init(root: URL = URL(fileURLWithPath: "/private/var/db/receipts"), requireRootOwnership: Bool = true,
         forgetCommand: @escaping @Sendable (String, TimeInterval) async throws -> Void = { id, timeout in
             let result = try await BoundedProcess.run("/usr/sbin/pkgutil", arguments: ["--forget", id], timeout: timeout, maximumOutputBytes: 65_536)
             guard result.status == 0 else { throw HelperRejection.executionFailed }
         }) {
        self.root = root; self.requireRootOwnership = requireRootOwnership; self.forgetCommand = forgetCommand
    }

    static func validIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count < 256 && id.first != "-"
            && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
            && id != "." && id != ".."
    }

    private func read(_ url: URL) throws -> Data {
        guard url.resolvingSymlinksInPath().path == url.standardizedFileURL.path else { throw HelperRejection.invalidPath }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= 32 * 1_024 * 1_024,
              !requireRootOwnership || ((attributes[.ownerAccountID] as? NSNumber)?.intValue == 0
                && ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o022 == 0)
        else { throw HelperRejection.invalidPath }
        return try Data(contentsOf: url)
    }

    func identity(for proof: PackageReceiptCleanupProof) async throws -> FileIdentity {
        guard Self.validIdentifier(proof.packageID) else { throw HelperRejection.invalidPath }
        return try await LocalFileSystem().identity(at: root.appendingPathComponent(proof.packageID + ".plist"))
    }

    func load(_ id: String) async throws -> PackageReceiptManifest {
        guard Self.validIdentifier(id) else { throw HelperRejection.invalidPath }
        let plistURL = root.appendingPathComponent(id + ".plist")
        let bomURL = root.appendingPathComponent(id + ".bom")
        let plistData = try read(plistURL), bomData = try read(bomURL)
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              plist["PackageIdentifier"] as? String == id,
              let prefix = plist["InstallPrefixPath"] as? String,
              !prefix.split(separator: "/").contains(".."),
              !prefix.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw HelperRejection.invalidPath }
        let output = try await BoundedProcess.run("/usr/bin/lsbom", arguments: ["-s", bomURL.path], timeout: 10, maximumOutputBytes: 16 * 1_024 * 1_024)
        guard output.status == 0, let text = String(data: output.stdout, encoding: .utf8),
              try read(plistURL) == plistData, try read(bomURL) == bomData else { throw HelperRejection.identityMismatch }
        let base = URL(fileURLWithPath: prefix.hasPrefix("/") ? prefix : "/" + prefix).standardizedFileURL
        let paths = try text.split(separator: "\n").map { entry -> URL in
            let relative = String(entry)
            guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."),
                  !relative.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw HelperRejection.invalidPath }
            return base.appendingPathComponent(relative).standardizedFileURL
        }
        guard !paths.isEmpty else { throw HelperRejection.invalidPath }
        return .init(packageID: id, fingerprint: SHA256.hash(data: plistData + bomData).map { String(format: "%02x", $0) }.joined(), paths: paths)
    }

    func forget(_ proof: PackageReceiptCleanupProof, scope: HelperFileScope, expiresAt: Date) async throws {
        guard !proof.applications.isEmpty, proof.applications.allSatisfy({ scope.isApplication($0.path) }) else { throw HelperRejection.invalidPath }
        let manifest = try await load(proof.packageID)
        guard manifest.proof(selectedApplications: Set(proof.applications)) == proof else { throw HelperRejection.identityMismatch }
        // All installed app roots must really be absent, including dangling links.
        // Permission errors are not treated as absence. Also reject redirected parents.
        for app in proof.applications {
            guard app.deletingLastPathComponent().resolvingSymlinksInPath() == app.deletingLastPathComponent() else { throw HelperRejection.invalidPath }
            var facts = stat()
            guard lstat(app.path, &facts) != 0, errno == ENOENT else { throw HelperRejection.invalidPath }
        }
        guard Date() < expiresAt else { throw HelperRejection.expired }
        try await forgetCommand(proof.packageID, min(10, expiresAt.timeIntervalSinceNow))
    }
}

/// Installer metadata never becomes a generic file-deletion capability. Each
/// selected receipt row still gets a durable success, retained, or failure result.
public struct PackageReceiptCleanupService: Sendable {
    private let load: @Sendable (String) async throws -> PackageReceiptManifest
    private let forget: @Sendable (PackageReceiptCleanupProof, UUID) async throws -> Void
    private let log: @Sendable (String) -> Void
    public init(forget: @escaping @Sendable (PackageReceiptCleanupProof, UUID) async throws -> Void) {
        self.init(load: { try await PackageReceiptStore().load($0) }, forget: forget,
            log: { Logger(subsystem: "SuperCleaner", category: "InstallationReceipts").debug("\($0, privacy: .private)") })
    }
    init(load: @escaping @Sendable (String) async throws -> PackageReceiptManifest,
         forget: @escaping @Sendable (PackageReceiptCleanupProof, UUID) async throws -> Void,
         log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.load = load; self.forget = forget; self.log = log
    }

    public func prepare(plan: CleanupPlan) async -> [PackageReceiptCleanupProof] {
        let applications = plan.selectedItems.map(\.candidate).filter { $0.source == .application && $0.category == .application }
        let paths = Set(applications.map { $0.url.standardizedFileURL })
        let ids = PackageReceiptCleanupSelection.requestedPackageIDs(in: plan)
        var proofs = [PackageReceiptCleanupProof]()
        for id in ids.sorted() {
            guard !Task.isCancelled else { break }
            do {
                if let proof = try await load(id).proof(selectedApplications: paths) { proofs.append(proof) }
            } catch { log("Receipt preparation skipped: \(id): \(error)") }
        }
        return proofs
    }

    @discardableResult
    public func finish(proofs: [PackageReceiptCleanupProof], receipt: OperationReceipt,
                       requestedReceiptURLs: [URL]? = nil,
                       permissionRecovery: CleanupExecutor.PermissionRecoveryHandler? = nil,
                       expiresAt: Date? = nil,
                       now: @Sendable () -> Date = Date.init,
                       progress: @Sendable (Int, URL?) -> Void = { _, _ in }) async -> [OperationResult] {
        let removed = Set(receipt.results.filter {
            $0.status == .succeeded && $0.verificationNotBefore == nil
                && [.quarantined, .trashed, .permanentlyDeleted].contains($0.disposition)
        }.map { $0.originalURL.standardizedFileURL })
        let urls = requestedReceiptURLs ?? proofs.flatMap { PackageReceiptCleanupSelection.receiptURLs(for: $0.packageID) }
        let grouped = Dictionary(grouping: urls.filter { PackageReceiptCleanupSelection.packageID(for: $0) != nil }) {
            PackageReceiptCleanupSelection.packageID(for: $0)!
        }
        let byID = Dictionary(proofs.map { ($0.packageID, $0) }, uniquingKeysWith: { first, _ in first })
        var results = [OperationResult]()
        for id in grouped.keys.sorted() {
            let requested = grouped[id]!
            progress(results.count, requested.first)
            let status: OperationStatus
            let message: String
            if Task.isCancelled {
                status = .skippedCancelled
                message = L10n.text("用户停止了尚未开始的项目")
            } else if let proof = byID[id] {
                if Set(proof.applications).isSubset(of: removed) {
                    do {
                        var attempt = 0
                        while true {
                            try Task.checkCancellation()
                            if let expiresAt, now() >= expiresAt { throw HelperRejection.expired }
                            do { try await forget(proof, receipt.planID); break }
                            catch {
                                guard UninstallPermissionRequest.isPermissionDenied(error), let permissionRecovery else { throw error }
                                attempt += 1
                                let decision = await permissionRecovery(.init(url: requested[0], resource: .installationReceipts,
                                    cause: .administratorAuthorization, attempt: attempt))
                                if case .stop = decision {
                                    withUnsafeCurrentTask { $0?.cancel() }
                                    throw CancellationError()
                                }
                                // The service validates the live receipt proof and
                                // app absence again on every authorized attempt.
                            }
                        }
                        status = .succeeded
                        message = L10n.text("已通过系统安装服务清理安装凭据")
                    } catch {
                        log("Receipt cleanup skipped: \(id): \(error)")
                        status = Task.isCancelled ? .skippedCancelled : .failed
                        message = Task.isCancelled ? L10n.text("用户停止了尚未开始的项目")
                            : L10n.text("安装凭据未清理：{0}", error.localizedDescription)
                    }
                } else {
                    status = .skippedProtected
                    message = L10n.text("应用本体未删除，安装凭据已保留。")
                }
            } else {
                status = .skippedProtected
                message = L10n.text("未能验证安装凭据，已保留。")
            }
            results.append(contentsOf: requested.map { url in
                OperationResult(candidateID: UUID(), originalURL: url,
                    disposition: status == .succeeded ? .permanentlyDeleted : status == .failed ? .failed : .skipped,
                    status: status, bytes: 0, message: message)
            })
            progress(results.count, nil)
        }
        return results
    }
}

/// A package's BOM and plist are one system-managed receipt. Both checkboxes
/// control the same option; neither file becomes a generic deletion candidate.
public struct PackageReceiptCleanupSelection: Equatable, Sendable {
    private var selectedPackageIDs = Set<String>()
    public init() {}

    public static func selectableReceipts(for installation: ApplicationInstallation?) -> [URL] {
        guard let installation, installation.source == .packageInstaller else { return [] }
        return installation.receipts.filter { packageID(for: $0) != nil }
    }

    public static func packageID(for receipt: URL) -> String? {
        guard ["/var/db/receipts", "/private/var/db/receipts"].contains(receipt.deletingLastPathComponent().standardizedFileURL.path),
              ["bom", "plist"].contains(receipt.pathExtension) else { return nil }
        let id = receipt.deletingPathExtension().lastPathComponent
        return PackageReceiptStore.validIdentifier(id) ? id : nil
    }

    public func isSelected(_ packageID: String) -> Bool { selectedPackageIDs.contains(packageID) }

    public mutating func setSelected(_ selected: Bool, packageID: String) {
        if selected { selectedPackageIDs.insert(packageID) }
        else { selectedPackageIDs.remove(packageID) }
    }

    public func applying(to candidate: CleanupCandidate, receiptURLs: [URL] = []) -> CleanupCandidate {
        guard candidate.source == .application else { return candidate }
        let evidence = candidate.evidence.filter { !["package-receipt-selected", "package-receipt-selected-path"].contains($0.code) }
        let ids = Set(receiptURLs.compactMap(Self.packageID))
            .union(evidence.filter { $0.code == "package-receipt-id" }.map(\.summary))
            .filter { isSelected($0) }
        let selected = ids.sorted().map { Evidence(code: "package-receipt-selected", summary: $0) }
        let paths = receiptURLs.filter { Self.packageID(for: $0).map(ids.contains) == true }
            .map { Evidence(code: "package-receipt-selected-path", summary: $0.path) }
        return candidate.replacing(risk: candidate.risk, evidence: evidence + selected + paths)
    }

    static func receiptURLs(for id: String) -> [URL] {
        ["plist", "bom"].map { URL(fileURLWithPath: "/private/var/db/receipts/\(id).\($0)") }
    }

    public static func requestedPackageIDs(in plan: CleanupPlan) -> Set<String> {
        Set(plan.selectedItems.filter { $0.candidate.source == .application }.flatMap { $0.candidate.evidence }
            .filter { $0.code == "package-receipt-selected" && PackageReceiptStore.validIdentifier($0.summary) }.map(\.summary))
    }

    public static func requestedReceiptURLs(in plan: CleanupPlan) -> [URL] {
        let evidence = plan.selectedItems.flatMap { $0.candidate.evidence }.filter { $0.code == "package-receipt-selected-path" }
        return requestedPackageIDs(in: plan).sorted().flatMap { id in
            let explicit = Set(evidence.compactMap { value -> URL? in
                let url = URL(fileURLWithPath: value.summary)
                guard packageID(for: url) == id else { return nil }
                return URL(fileURLWithPath: "/private/var/db/receipts/\(url.lastPathComponent)")
            })
            return explicit.isEmpty ? receiptURLs(for: id) : explicit.sorted { $0.path < $1.path }
        }
    }
}

public extension CleanupPlan {
    var selectedDisplayItemCount: Int {
        selectedItems.count + PackageReceiptCleanupSelection.requestedReceiptURLs(in: self).count
    }
}
