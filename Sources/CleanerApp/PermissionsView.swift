import CleanerCore
import SwiftUI

struct PermissionsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmsHelperInstall = false
    @State private var confirmsHelperRegistration = false
    @AppStorage(AppLanguage.preferenceKey) private var languagePreference = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("设置")).font(.largeTitle.bold())
                Text(L10n.text("管理扫描权限、大文件标准和已删除项目保留时间。"))
                    .foregroundColor(.secondary)
            }
            .padding(24)
            Divider()
            Form {
                languageSection
                versionSection
                agentOverlapSection
                PermissionAccessSection(model: model)
                helperSection
                    .disabled(model.updateInProgress)
                UpdateSettingsSection(model: model.updates)
                ApplicationUpdateSettingsSection(model: model.applicationUpdates)
                protectionSection
                    .disabled(model.updateInProgress)
                largeFileSection
                quarantineSection
            }
            .formStyle(.grouped)
            .task { await model.loadPermissions() }
            .alert(L10n.text("安装受限 Helper？"), isPresented: $confirmsHelperInstall) {
                Button(L10n.text("取消"), role: .cancel) {}
                Button(L10n.text("请求系统注册")) { model.helper.install() }
            } message: {
                Text(L10n.text("macOS 需要管理员批准后台 Helper。它只支持应用与本用户恢复区间的受限操作；注册不会自动启动清理。临时签名构建不可启用。"))
            }
            .alert(L10n.text("重新注册本版本 Helper？"), isPresented: $confirmsHelperRegistration) {
                Button(L10n.text("取消"), role: .cancel) {}
                Button(L10n.text("重新注册")) { model.helper.reregisterAfterUpgrade() }
            } message: { Text(L10n.text("先解除旧注册，再注册当前版本。系统可能要求重新批准；失败时保持未启用，不恢复旧授权。")) }
        }
    }

    private var helperSection: some View {
        HelperSettingsSection(
            helper: model.helper,
            operationsBusy: model.phase == .executing || model.isScanRunning,
            requestInstall: { confirmsHelperInstall = true },
            requestReregistration: { confirmsHelperRegistration = true }
        )
    }

    private var languageSection: some View {
        Section(L10n.text("语言")) {
            Picker(L10n.text("界面语言"), selection: Binding(
                get: { AppLanguage(rawValue: languagePreference) ?? .english },
                set: { languagePreference = $0.rawValue }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.nativeName).tag(language)
                }
            }
            Text(L10n.text("默认使用英语。语言更改将在下次启动时生效。"))
                .font(.caption).foregroundColor(.secondary)
            if (AppLanguage(rawValue: languagePreference) ?? .english) != L10n.language {
                Label(L10n.text("语言已保存；请在当前操作完成后退出并重新打开应用。"), systemImage: "arrow.clockwise")
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }

    private var versionSection: some View {
        Section(L10n.text("版本信息")) {
            LabeledContent(L10n.text("应用版本"), value: AppVersion.current.version)
            LabeledContent(L10n.text("构建号"), value: AppVersion.current.build)
        }
    }

    private var agentOverlapSection: some View {
        Section(L10n.text("Agent 功能重叠分析")) {
            LabeledContent(L10n.text("本机模型状态"), value: model.agentOverlapStatus)
            if !model.agentOverlapSupportedPlatform {
                Text(L10n.text("Agent 能力分析需要 macOS 14 或更高版本及 Apple Silicon；其他功能可正常使用。"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Text(L10n.text("使用 Google EmbeddingGemma 2 在本机分析 Skill 与 MCP 的功能覆盖。约 310 MB 模型已随 App 打包，首次使用无需下载；不连接 MCP 服务。"))
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Stepper(value: Binding(
                    get: { Int(model.agentOverlapThreshold * 100) },
                    set: { model.updateAgentOverlapThreshold(Double($0) / 100) }
                ), in: 50...100) {
                    Text(L10n.text("覆盖阈值")) + Text(": \(Int(model.agentOverlapThreshold * 100))%")
                }
                .disabled(!model.agentOverlapSupportedPlatform)
                if model.agentOverlapModelCanRemove {
                    Button(L10n.text("移除本机下载副本")) {
                        let task = model.removeAgentOverlapModel()
                        Task { model.finishAgentOverlapTask(await task.result) }
                    }
                    .disabled(model.agentOverlapModelDownloadInProgress)
                }
            }
            if model.agentOverlapSupportedPlatform && !model.agentOverlapModelInstalled {
                HStack {
                    Button(L10n.text("下载并启用模型")) { model.startAgentOverlapModelDownload() }
                        .disabled(model.agentOverlapModelDownloadInProgress)
                    if model.agentOverlapModelDownloadInProgress {
                        Button(L10n.text("取消下载")) { model.cancelAgentOverlapModelDownload() }
                    }
                }
                if model.agentOverlapModelDownloadInProgress {
                    ProgressView(value: model.agentOverlapModelDownloadProgress ?? 0)
                    Text(L10n.text("下载进度：{0}%", String(describing: Int((model.agentOverlapModelDownloadProgress ?? 0) * 100))))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Button(L10n.text("重新计算全部包含关系"), action: model.recalculateAllAgentContainment)
                .disabled(!model.canRecalculateAgentContainment)
            Text(L10n.text("Skill 与 MCP 使用同一阈值：能力被其他同类对象联合包含达到阈值时默认勾选。普通扫描复用已知关系，仅分析新增对象；此按钮重新扫描 Agent 资源并重建全部关系。最终清理仍需你确认。"))
                .font(.caption).foregroundColor(.secondary)
        }
    }
}

private struct HelperSettingsSection: View {
    @ObservedObject var helper: HelperSettingsModel
    let operationsBusy: Bool
    let requestInstall: () -> Void
    let requestReregistration: () -> Void

    var body: some View {
        Section(L10n.text("受限 Helper")) {
            LabeledContent(L10n.text("系统状态"), value: helper.status.title)
            Text(L10n.text("仅在需要权限的应用隔离、恢复和清除中使用。注册、连接验证与操作授权是三个独立步骤；不提供任意系统删除、服务终止或脚本执行。"))
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Button(L10n.text("安装…"), action: requestInstall)
                    .disabled(helper.status == .enabled || helper.status == .requiresApproval || helper.status == .unavailable)
                Button(L10n.text("打开系统批准…")) { helper.openApprovalSettings() }
                Button(L10n.text("重新注册…"), action: requestReregistration)
                    .disabled(helper.status != .enabled && helper.status != .requiresApproval)
                Button(L10n.text("移除")) { helper.remove() }
                    .disabled(helper.status != .enabled && helper.status != .requiresApproval)
            }.disabled(helper.isChanging || operationsBusy)
            if helper.authorizationActive {
                Label(L10n.text("本次会话已授权（最多 5 分钟）"), systemImage: "lock.open")
                Button(L10n.text("立即关闭授权")) { helper.revokeSession() }.disabled(operationsBusy)
            } else {
                Button(L10n.text("验证连接并授权本次会话…")) { helper.authorizeSession() }
                    .disabled(helper.status != .enabled || helper.isChanging || operationsBusy)
            }
            if let message = helper.message { Text(message).font(.caption).textSelection(.enabled) }
            if helper.status == .unavailable || helper.status == .notFound {
                Text(L10n.text("需要正式 Bundle ID、同团队证书签名和公证的完整应用包；当前开发构建不具备真实安装验收条件。"))
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }
}

extension PermissionsView {
    private var protectionSection: some View {
        Section(L10n.text("永久保护")) {
            Text(L10n.text("受保护的文件、目录及其内容不会进入删除计划。凭证、系统关键目录和本应用恢复数据始终受到保护。"))
                .font(.caption).foregroundColor(.secondary)
            ForEach(model.protectionPolicy.entries) { entry in
                HStack {
                    Text(entry.url.path).textSelection(.enabled)
                    Spacer()
                    Button(L10n.text("取消保护")) { model.removeProtection(entry) }
                        .disabled(model.phase == .executing)
                }
            }
            Button(L10n.text("添加文件或目录…")) { model.chooseProtectedPath() }
            if let message = model.configurationMessage { Text(message).font(.caption) }
            if !model.protectionPolicy.isAvailable {
                Label(L10n.text("保护清单无法读取，当前禁止删除"), systemImage: "lock.trianglebadge.exclamationmark").foregroundColor(.orange)
            }
            Text(L10n.text("当前规则：{0}", String(describing: model.rulesetVersion.split(separator: ":").first.map(String.init) ?? model.rulesetVersion)))
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var largeFileSection: some View {
        Section(L10n.text("大文件")) {
            Picker(
                L10n.text("文件体积标准"),
                selection: Binding(
                    get: { model.largeFileThreshold },
                    set: { model.updateLargeFileThreshold($0) }
                )
            ) {
                ForEach(LargeFileThreshold.allCases, id: \.self) { threshold in
                    Text(threshold.displayTitle).tag(threshold)
                }
            }
            Text(L10n.text("只把达到该体积的具体文件列为大文件并允许加入计划。扫描只读取目录和大小元数据，不读取文件内容。"))
                .font(.caption)
                .foregroundColor(.secondary)
            if model.largeFileThresholdNeedsRefresh {
                HStack {
                    Label(L10n.text("当前结果仍使用上一次扫描的标准"), systemImage: "arrow.triangle.2.circlepath")
                        .foregroundColor(.orange)
                    Spacer()
                    Button(L10n.text("应用并刷新")) { model.refreshModule(.largeFiles) }
                        .disabled(model.isScanRunning)
                }
            }
        }
    }

    private var quarantineSection: some View {
        Section(L10n.text("删除与恢复")) {
            Picker(
                L10n.text("已删除项目保留时间"),
                selection: Binding(
                    get: { model.defaultQuarantineRetentionPolicy },
                    set: { model.updateDefaultQuarantineRetentionPolicy($0) }
                )
            ) {
                ForEach(QuarantineRetentionPolicy.allCases, id: \.self) { policy in
                    Text(policy.displayTitle).tag(policy)
                }
            }
            Text(L10n.text("默认立即删除：新清理项目会在安全校验与记录保存后移入 macOS 系统废纸篓。可选择保留时间；更改默认值不会影响已有恢复记录。"))
                .font(.caption).foregroundColor(.secondary)
            if model.defaultQuarantineRetentionPolicy == .immediate {
                Label(L10n.text("项目将移入系统废纸篓，可在清空废纸篓前恢复。"), systemImage: "trash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

}

private struct PermissionAccessSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section(L10n.text("权限")) {
            Text(L10n.text("完全磁盘访问需在系统设置中开启；返回 App 后会自动重新检查，未授权区域会安全跳过。"))
                .font(.caption)
                .foregroundColor(.secondary)
            PermissionRow(
                icon: "folder.badge.questionmark",
                title: L10n.text("完全磁盘访问"),
                detail: model.permissionSnapshot?.fullDiskAccess.explanation ?? L10n.text("点击全扫描时检查权限"),
                state: model.permissionSnapshot?.fullDiskAccess.status == .actionRequired
                    ? L10n.text("访问检查未通过") : permissionStateTitle(model.permissionSnapshot?.fullDiskAccess.status),
                stateColor: permissionStateColor(model.permissionSnapshot?.fullDiskAccess.status)
            ) {
                Button(L10n.text("打开系统设置…")) { model.openFullDiskAccessSettings() }
                    .controlSize(.small)
            }
            PermissionRow(
                icon: "app.badge.checkmark",
                title: L10n.text("App 管理"),
                detail: L10n.text("执行卸载时由系统确认"),
                state: nil,
                stateColor: .secondary
            ) {
                Button(L10n.text("打开系统设置…")) { model.openAppManagementSettings() }
                    .controlSize(.small)
            }
        }
    }

    private func permissionStateTitle(_ status: PermissionCapabilityStatus?) -> String {
        return switch status {
        case .granted: L10n.text("可用")
        case .actionRequired: L10n.text("需要授权")
        case .unverified: L10n.text("尚未验证")
        case nil: L10n.text("尚未验证")
        }
    }

    private func permissionStateColor(_ status: PermissionCapabilityStatus?) -> Color {
        switch status {
        case .granted: .green
        case .actionRequired: .orange
        case .unverified, nil: .secondary
        }
    }

}
private struct PermissionRow<Action: View>: View {
    let icon: String
    let title: String
    let detail: String
    let state: String?
    let stateColor: Color
    @ViewBuilder let action: Action

    init(icon: String, title: String, detail: String, state: String?, stateColor: Color, @ViewBuilder action: () -> Action) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.state = state
        self.stateColor = stateColor
        self.action = action()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let state { Text(state).foregroundColor(stateColor) }
                action
            }
        }
        .padding(.vertical, 4)
    }
}
