import CleanerCore
import SwiftUI

/// One sheet owns the whole operation so progress switches directly to its
/// receipt (or an error) without competing sheet presentations.
struct DeletionOperationSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.isDeletionInProgress {
                if let request = model.uninstallPermissionRequest {
                    UninstallPermissionGuidance(model: model, helper: model.helper, request: request)
                } else {
                    progress
                }
            } else if let receipt = model.deletionResult {
                DeletionResultSheet(model: model, receipt: receipt)
            } else if model.deletionResultWarning != nil {
                failure
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .interactiveDismissDisabled(model.isDeletionInProgress)
    }

    private var progress: some View {
        let total = max(1, model.executionProgress.total)
        let completed = min(total, max(0, model.executionProgress.completed))
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(progressTitle)
                    .font(.title2.bold())
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(model.executionProgressDescription)
                    .font(.headline).monospacedDigit()
                if model.executionProgress.phase == .movingToTrash, model.executionProgress.currentURL != nil {
                    // macOS reports completion per item, not bytes copied within
                    // a single system Trash operation. Do not invent a fraction.
                    ProgressView().progressViewStyle(.linear)
                } else {
                    ProgressView(value: Double(completed), total: Double(total))
                        .progressViewStyle(ImmediateLinearProgressStyle())
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                if model.isStoppingDeletion {
                    Text(L10n.text("正在停止…")).fontWeight(.medium)
                    Text(L10n.text("当前项目处理结束后停止，已经完成的操作不会自动撤销。"))
                        .foregroundColor(.secondary)
                } else if model.executionProgress.phase == .savingResults {
                    Text(L10n.text("正在保存清理和恢复记录…")).foregroundColor(.secondary)
                } else if model.executionProgress.phase == .updatingResults {
                    Text(L10n.text("正在更新清理清单…")).foregroundColor(.secondary)
                } else if model.executionProgress.total > 0 && completed == total {
                    Text(L10n.text("正在保存清理和恢复记录…")).foregroundColor(.secondary)
                } else if let url = model.executionProgress.currentURL {
                    Text(url.lastPathComponent).fontWeight(.medium).lineLimit(2)
                    Text(url.path).font(.caption.monospaced()).foregroundColor(.secondary)
                        .textSelection(.enabled).lineLimit(3)
                    if let started = model.executionItemStartedAt {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text(L10n.text("当前文件已用 {0} 秒", String(max(0, Int(context.date.timeIntervalSince(started))))))
                                .font(.caption).foregroundColor(.secondary).monospacedDigit()
                        }
                    }
                } else {
                    Text(L10n.text("正在准备删除…")).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            Text(L10n.text("处理完成后会显示实际结果和各项目的恢复方式。"))
                .font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(model.isStoppingDeletion ? L10n.text("正在停止…") : L10n.text("停止后续项目")) {
                    model.cancelExecution()
                }
                .disabled(!model.canStopDeletion)
            }
        }
        .padding(28)
        .frame(width: 680)
    }

    private var progressTitle: String {
        switch model.executionProgress.phase {
        case .movingToTrash: L10n.text("正在移入系统废纸篓")
        case .savingResults: L10n.text("正在保存清理和恢复记录…")
        case .updatingResults: L10n.text("正在更新清理清单…")
        case .processing: model.activeCleanupModules == [.applications]
            ? L10n.text("正在删除应用内容") : L10n.text("正在检查并删除所选项目")
        }
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("删除未完成"), systemImage: "exclamationmark.circle")
                .font(.title2.bold()).foregroundColor(.orange)
            Text(model.deletionResultWarning ?? L10n.text("删除未完成"))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.text("查看恢复记录")) {
                    model.dismissDeletionSheet()
                    model.selection = .recovery
                }
                Spacer()
                Button(L10n.text("完成")) { model.dismissDeletionSheet() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 680)
    }
}

private struct UninstallPermissionGuidance: View {
    @ObservedObject var model: AppModel
    @ObservedObject var helper: HelperSettingsModel
    let request: UninstallPermissionRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(request.requiresAdministrator ? L10n.text("卸载已暂停，需要管理员权限")
                  : L10n.text("卸载已暂停，需要权限"), systemImage: "lock.shield")
                .font(.title2.bold()).foregroundColor(.orange)
            Text(model.executionProgressDescription).font(.headline).monospacedDigit()
            Text(request.url.path).font(.caption.monospaced()).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Text(guidance)
                .fixedSize(horizontal: false, vertical: true)
            if request.attempt > 1 && !request.requiresAdministrator {
                Text(L10n.text("系统仍拒绝访问。如果相关隐私权限已经开启，可能存在其他系统保护限制，请勿反复开启同一开关。"))
                    .foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Text(L10n.text("已完成的项目会保留；继续时会重新验证并重试当前项目，再处理剩余项目。"))
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if request.requiresAdministrator || request.isApplicationBundle {
                if !canUseAdministratorService {
                    Text(request.resource == .installationReceipts
                         ? L10n.text("当前版本无法启用管理员服务；应用文件的处理结果已保留，安装凭据会保留并记录为未完成。")
                         : request.resource == .applicationData
                         ? L10n.text("此类关联文件不通过管理员服务删除。可停止任务后在 Finder 中检查文件权限；已完成的结果会保留。")
                         : L10n.text("当前构建没有可用的管理员服务，无法在 App 内继续此项操作。可停止任务并在 Finder 中显示应用，由你完成需要管理员确认的移除。"))
                        .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if !request.requiresAdministrator && !helper.authorizationActive {
                    Button(L10n.text("管理员授权…")) { Task { await helper.prepareForScan() } }
                        .disabled(helper.isChanging || model.isStoppingDeletion)
                }
                if let message = helper.message {
                    Text(message).font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button(L10n.text("停止后续项目")) { model.cancelExecution() }
                    .disabled(!model.canStopDeletion)
                Spacer()
                if request.settingsURL != nil {
                    Button(L10n.text("打开系统设置…")) { model.openUninstallPermissionSettings() }
                }
                if request.requiresAdministrator && !canUseAdministratorService {
                    if request.resource != .installationReceipts {
                        Button(L10n.text("停止并在 Finder 中显示")) { model.stopUninstallAndRevealInFinder() }
                            .buttonStyle(.borderedProminent).disabled(!model.canStopDeletion)
                    }
                } else if request.requiresAdministrator && !helper.authorizationActive {
                    Button(L10n.text("管理员授权并继续…")) { Task { await model.authorizeAndContinueUninstall() } }
                        .buttonStyle(.borderedProminent).disabled(helper.isChanging || model.isStoppingDeletion)
                } else {
                    Button(L10n.text("已修改，继续卸载")) { model.continueUninstallAfterPermissionChange() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canContinueUninstallAfterPermissionChange)
                }
            }
        }
        .padding(28)
        .frame(width: 680)
        .onAppear { helper.refresh() }
    }

    private var canUseAdministratorService: Bool {
        request.supportsPrivilegedHelper && helper.status != .unavailable && helper.status != .notFound
    }

    private var guidance: String {
        if request.cause == .filePermissions {
            return L10n.text("系统文件权限拒绝移动此项目（EACCES，13）。开启 App 管理不会提升文件权限，需要管理员操作后才能继续。")
        }
        if request.cause == .administratorAuthorization && request.resource != .installationReceipts {
            return L10n.text("管理员操作尚未授权，或授权已过期。请完成管理员授权后继续卸载。")
        }
        return switch request.resource {
        case .applicationBundle:
            L10n.text("请在系统设置的“隐私与安全性 → App 管理”中允许 SuperCleaner 修改其他应用，然后返回继续。")
        case .applicationData:
            L10n.text("请检查系统设置的“隐私与安全性 → 完全磁盘访问权限”，允许 SuperCleaner 后返回继续。")
        case .installationReceipts:
            L10n.text("清理系统安装凭据需要管理员服务授权。完成授权后继续，只会重试安装凭据，不会重复删除应用文件。")
        }
    }
}
