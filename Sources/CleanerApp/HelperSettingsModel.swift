import CleanerCore
import Foundation

/// Owns the complete Helper registration and short-lived authorization lifecycle.
/// Callers only decide whether the surrounding application is currently idle;
/// signing, registration, XPC verification and session revocation stay behind this interface.
@MainActor final class HelperSettingsModel: ObservableObject {
    @Published private(set) var status: HelperRegistrationStatus = .unavailable
    @Published private(set) var authorizationActive = false
    @Published private(set) var isChanging = false
    @Published private(set) var message: String?

    private let manager: HelperServiceManager
    private let session: HelperAuthorizationSession
    private var refreshTask: Task<Void, Never>?
    private let statusReader: (@Sendable () async -> HelperRegistrationStatus)?
    private var canChange: @MainActor () -> Bool = { true }

    init(
        manager: HelperServiceManager = HelperServiceManager(),
        session: HelperAuthorizationSession = HelperAuthorizationSession(),
        statusReader: (@Sendable () async -> HelperRegistrationStatus)? = nil
    ) {
        self.manager = manager
        self.session = session
        self.statusReader = statusReader
    }

    func configureAvailability(_ canChange: @escaping @MainActor () -> Bool) {
        self.canChange = canChange
    }

    func authorizedApplicationOperations(fileSystem: any FileSystemAccess) -> AuthorizedApplicationOperations {
        AuthorizedApplicationOperations(
            session: session,
            registrationEnabled: { [weak self] in await MainActor.run { self?.status == .enabled } },
            identity: try? HelperSigningIdentity.current(),
            fileSystem: fileSystem
        )
    }

    func refresh() {
        guard refreshTask == nil, !isChanging else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { refreshTask = nil } }
            let updated: HelperRegistrationStatus
            if let statusReader { updated = await statusReader() }
            else { updated = await manager.readStatus() }
            guard !Task.isCancelled else { return }
            if status != updated { status = updated }
            if updated != .enabled { session.revoke() }
            let authorized = session.isAuthorized
            if authorizationActive != authorized { authorizationActive = authorized }
        }
    }

    func install() {
        guard beginChange() else { return }
        defer { finishChange() }
        do {
            try manager.install()
            message = L10n.text("已请求系统注册；请在系统设置中批准后验证连接。注册不等于操作已获授权。")
        } catch {
            message = L10n.text("Helper 未安装：{0}", String(describing: error.localizedDescription))
        }
    }

    func remove() {
        guard beginChange(revoking: true) else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { finishChange() }
            do {
                try await manager.remove()
                message = L10n.text("Helper 已解除注册；恢复记录和隔离文件保持原样。")
            } catch {
                message = L10n.text("Helper 解除注册未完成：{0}", String(describing: error.localizedDescription))
            }
        }
    }

    func reregisterAfterUpgrade() {
        guard beginChange(revoking: true) else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { finishChange() }
            do {
                try await manager.reregisterAfterUpgrade()
                message = L10n.text("已重新注册本版本 Helper；系统可能要求重新批准。")
            } catch {
                message = L10n.text("Helper 重新注册失败：{0}", String(describing: error.localizedDescription))
            }
        }
    }

    func authorizeSession() {
        Task { await prepareForScan() }
    }

    /// Invoked only from the user's permission preparation action.
    @discardableResult func prepareForScan() async -> Bool {
        guard beginChange() else { return false }
        defer { finishChange() }
        do {
            status = await manager.readStatus()
            if status == .notRegistered { try manager.install(); status = manager.status }
            if status == .requiresApproval {
                manager.openApprovalSettings()
                message = L10n.text("请在系统设置中批准后台服务，然后返回继续。")
                return false
            }
            guard status == .enabled else { throw HelperClientError.unavailable }
            let identity = try HelperSigningIdentity.current()
            _ = try await XPCPrivilegedHelperClient(identity: identity).ping()
            guard canChange() else { throw HelperClientError.unavailable }
            try session.authorizeUserInteraction()
            authorizationActive = session.isAuthorized
            message = L10n.text("本次使用期间复用管理员授权；退出应用、主动关闭或系统撤销后失效。")
            return authorizationActive
        } catch {
            session.revoke(); authorizationActive = false
            message = L10n.text("Helper 会话未启用：{0}", error.localizedDescription)
            return false
        }
    }

    func refreshForScan() async {
        guard !isChanging else { return }
        refreshTask?.cancel(); refreshTask = nil
        status = await manager.readStatus()
        if status != .enabled { session.revoke() }
        authorizationActive = session.isAuthorized
    }

    func revokeSession() {
        session.revoke()
        authorizationActive = false
        message = L10n.text("已关闭本次特权操作授权；普通扫描和恢复记录仍可使用。")
    }

    func openApprovalSettings() { manager.openApprovalSettings() }

    func prepareForApplicationUpdate() async throws {
        session.revoke()
        authorizationActive = false
        try await manager.remove()
        refresh()
    }

    var isStopped: Bool { [.notRegistered, .notFound].contains(manager.status) }

    private func beginChange(revoking: Bool = false) -> Bool {
        guard !isChanging, canChange() else { return false }
        refreshTask?.cancel()
        refreshTask = nil
        if revoking {
            session.revoke()
            authorizationActive = false
        }
        isChanging = true
        return true
    }

    private func finishChange() {
        isChanging = false
        refresh()
    }
}

private actor HelperRefreshProbe {
    private(set) var count = 0
    func read() async -> HelperRegistrationStatus {
        count += 1
        try? await Task.sleep(for: .milliseconds(150))
        return .enabled
    }
}

extension HelperSettingsModel {
    static func checkActivationRefresh() async throws {
        struct Failure: Error { }
        let probe = HelperRefreshProbe()
        let model = HelperSettingsModel(statusReader: { await probe.read() })
        var publications = 0
        let observation = model.objectWillChange.sink { publications += 1 }
        let start = Date()
        for _ in 0..<20 { model.refresh() }
        guard Date().timeIntervalSince(start) < 0.05 else { throw Failure() }
        // The main actor remains available while the status request is pending.
        try await Task.sleep(for: .milliseconds(20))
        guard await probe.count == 1, model.status == .unavailable else { throw Failure() }
        await model.refreshTask?.value
        guard model.status == .enabled, publications == 1 else { throw Failure() }
        model.refresh()
        await model.refreshTask?.value
        guard await probe.count == 2, publications == 1 else { throw Failure() }
        observation.cancel()
        print("PASS: activation status refresh is nonblocking, coalesces repeated requests and does not republish unchanged status")
    }
}
