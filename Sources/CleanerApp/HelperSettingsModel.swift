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
    private var canChange: @MainActor () -> Bool = { true }

    init(
        manager: HelperServiceManager = HelperServiceManager(),
        session: HelperAuthorizationSession = HelperAuthorizationSession()
    ) {
        self.manager = manager
        self.session = session
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
        status = manager.status
        if status != .enabled { session.revoke() }
        authorizationActive = session.isAuthorized
    }

    func install() {
        guard beginChange() else { return }
        defer { finishChange() }
        do {
            try manager.install()
            message = "已请求系统注册；请在系统设置中批准后验证连接。注册不等于操作已获授权。"
        } catch {
            message = "Helper 未安装：\(error.localizedDescription)"
        }
    }

    func remove() {
        guard beginChange(revoking: true) else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { finishChange() }
            do {
                try await manager.remove()
                message = "Helper 已解除注册；恢复记录和隔离文件保持原样。"
            } catch {
                message = "Helper 解除注册未完成：\(error.localizedDescription)"
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
                message = "已重新注册本版本 Helper；系统可能要求重新批准。"
            } catch {
                message = "Helper 重新注册失败：\(error.localizedDescription)"
            }
        }
    }

    func authorizeSession() {
        guard beginChange() else { return }
        Task { [weak self] in
            guard let self else { return }
            defer { finishChange() }
            do {
                guard manager.status == .enabled else { throw HelperClientError.unavailable }
                let identity = try HelperSigningIdentity.current()
                _ = try await XPCPrivilegedHelperClient(identity: identity).ping()
                guard canChange() else { throw HelperClientError.unavailable }
                try session.authorizeUserInteraction()
                message = "已验证同团队 Helper 并启用最多 5 分钟的受限应用操作；具体项目仍需明确选择、确认和复验。"
            } catch {
                session.revoke()
                message = "Helper 会话未启用：\(error.localizedDescription)"
            }
        }
    }

    func revokeSession() {
        session.revoke()
        authorizationActive = false
        message = "已关闭本次特权操作授权；普通扫描和恢复记录仍可使用。"
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
