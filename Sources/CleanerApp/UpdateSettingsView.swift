import AppKit
import CleanerCore
import SwiftUI

@MainActor final class UpdateSettingsModel: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var currentRuleVersion = L10n.text("正在读取")
    @Published private(set) var rollbackAvailable = false
    @Published private(set) var receivedBytes: Int64 = 0
    @Published private(set) var expectedBytes: Int64?
    @Published private(set) var message: String?
    @Published private(set) var configuration: ReleaseConfiguration?
    private let runtime: CleanupRuntime
    private let canStart: @MainActor () -> Bool
    private let activityChanged: @MainActor (Bool) -> Void
    private let activated: @MainActor (RulePack) -> Void
    private var task: Task<Void, Never>?
    private var generation: UUID?

    init(runtime: CleanupRuntime, canStart: @escaping @MainActor () -> Bool,
         activityChanged: @escaping @MainActor (Bool) -> Void, activated: @escaping @MainActor (RulePack) -> Void) {
        self.runtime = runtime; self.canStart = canStart; self.activityChanged = activityChanged; self.activated = activated
        do {
            configuration = try ReleaseConfiguration.load()
            if configuration == nil { message = L10n.text("签名更新尚未配置；仍可使用随包规则。更新源与公钥由发布配置提供，不在界面信任未知密钥。") }
        } catch { message = L10n.text("更新配置不可用：{0}", String(describing: error.localizedDescription)) }
    }
    var canUpdateRules: Bool { !isBusy && canStart() && configuration?.ruleUpdateURL != nil }
    var canImportRules: Bool { !isBusy && canStart() && configuration?.rulePublicKey?.count == 32 }
    var canRollback: Bool { !isBusy && canStart() && rollbackAvailable }
    func refresh() {
        guard !isBusy else { return }
        Task { await refreshState() }
    }
    private func refreshState() async {
        do {
            currentRuleVersion = try await runtime.rules.currentVersion()
        } catch { currentRuleVersion = L10n.text("无法验证"); message = L10n.text("当前规则无法验证：{0}", String(describing: error.localizedDescription)) }
        rollbackAvailable = (try? await runtime.rules.canRollback()) ?? false
    }
    func downloadRules() {
        guard canUpdateRules, configuration != nil else { return }
        run { service, progress in try await service.update(progress: progress) }
    }
    func importRules() {
        guard canImportRules else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.prompt = L10n.text("验签并导入")
        guard panel.runModal() == .OK, let url = panel.url, canImportRules else { return }
        run { service, _ in try await service.importUpdate(at: url) }
    }
    func rollbackRules() {
        guard canRollback else { return }
        run { service, _ in try await service.rollback() }
    }
    func cancel() { task?.cancel() }
    private func run(_ operation: @escaping @Sendable (RuleUpdateService, @escaping @Sendable (Int64, Int64?) -> Void) async throws -> RulePack) {
        guard !isBusy, canStart(), let configuration else { return }
        isBusy = true; activityChanged(true); receivedBytes = 0; expectedBytes = nil
        let token = UUID(); generation = token
        message = L10n.text("正在验证签名规则；当前规则在提交前保持不变。")
        let service = RuleUpdateService(store: runtime.rules, configuration: configuration)
        task = Task { [weak self] in
            guard let self else { return }
            defer { isBusy = false; generation = nil; task = nil; activityChanged(false) }
            do {
                let previousIdentity = try? await runtime.rules.currentPack().executionVersion
                let pack = try await operation(service, { [weak self] bytes, expected in
                    Task { @MainActor [weak self] in
                        guard let self, generation == token else { return }
                        receivedBytes = bytes; expectedBytes = expected
                    }
                })
                if pack.executionVersion != previousIdentity {
                    activated(pack)
                    message = L10n.text("规则 {0} 已启用；旧扫描与计划已失效，请重新扫描。历史撤销仍受保护。", String(describing: pack.version))
                } else { message = L10n.text("当前已是规则 {0}，未更改扫描或选择。", String(describing: pack.version)) }
            } catch is CancellationError { message = L10n.text("未提交的规则更新已取消；已完成的原子提交需显式回滚。") }
            catch { message = L10n.text("规则更新未完成：{0}。当前已验证规则保持原样。", String(describing: error.localizedDescription)) }
            await refreshState()
        }
    }
}

struct UpdateSettingsSection: View {
    @ObservedObject var model: UpdateSettingsModel
    @State private var confirmsRollback = false
    var body: some View {
        Section(L10n.text("签名更新")) {
            LabeledContent(L10n.text("规则版本"), value: model.currentRuleVersion)
            if let host = model.configuration?.ruleUpdateURL?.host {
                LabeledContent(L10n.text("规则来源"), value: host)
            } else { Text(L10n.text("规则网络更新未配置")).font(.caption).foregroundColor(.secondary) }
            HStack {
                Button(L10n.text("更新规则")) { model.downloadRules() }.disabled(!model.canUpdateRules)
                Button(L10n.text("导入已签名规则…")) { model.importRules() }.disabled(!model.canImportRules)
                Button(L10n.text("回滚规则…")) { confirmsRollback = true }.disabled(!model.canRollback)
                if model.isBusy { Button(L10n.text("取消下载")) { model.cancel() } }
            }
            if model.isBusy {
                ProgressView()
                Text(L10n.text("已接收 {0}", ByteCountFormatter.cleanerString(bytes: UInt64(max(0, model.receivedBytes))))).font(.caption)
            }
            if let message = model.message { Text(message).font(.caption).textSelection(.enabled) }
            Text(L10n.text("只信任发布配置中的 Ed25519 公钥；下载失败、验签失败或普通旧包重放不会替换当前包。回滚保留历史撤销，并使旧计划失效。"))
                .font(.caption).foregroundColor(.secondary)
        }
        .onAppear { model.refresh() }
        .alert(L10n.text("回滚到上一份已验证规则？"), isPresented: $confirmsRollback) {
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("回滚")) { model.rollbackRules() }
        } message: { Text(L10n.text("旧扫描与计划会失效；已撤销规则不会因回滚重新启用。网络更新也不能重放已回滚的包。")) }
    }
}

struct ApplicationUpdateSettingsSection: View {
    @ObservedObject var model: ApplicationUpdateModel
    @State private var confirmsCheck = false
    var body: some View {
        Section(L10n.text("应用更新")) {
            if let host = model.source { LabeledContent(L10n.text("更新来源"), value: host) }
            Button(L10n.text("检查应用更新…")) { confirmsCheck = true }.disabled(!model.canCheck)
            if model.isBusy { ProgressView() }
            Text(model.message).font(.caption).textSelection(.enabled)
        }
        .alert(L10n.text("准备检查并更新应用？"), isPresented: $confirmsCheck) {
            Button(L10n.text("取消"), role: .cancel) {}
            Button(L10n.text("解除 Helper 注册并检查")) { model.check() }
        } message: {
            Text(L10n.text("本操作先关闭特权会话、解除 Helper 注册；恢复记录保持不变。之后由更新窗口确认下载和安装。取消、失败或升级后都需在设置中手动重新启用 Helper。"))
        }
    }
}
