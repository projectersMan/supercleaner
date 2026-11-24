import CleanerCore
import Foundation
import SwiftUI

struct PermissionsView: View {
    @ObservedObject var model: AppModel
    @State private var confirmsHelperInstall = false
    @State private var confirmsHelperRegistration = false
    @AppStorage(AppLanguage.preferenceKey) private var languagePreference = AppLanguage.english.rawValue
    @AppStorage(TrashReminderState.suppressionPreferenceKey) private var suppressTrashReminder = false
    @State private var projectRootsDraft: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("设置")).font(.largeTitle.bold())
            }
            .padding(24)
            Divider()
            Form {
                projectScanRootsSection
                ModelStorageRootsSettingsSection(model: model)
                largeFileSection
                quarantineSection
                protectionSection
                    .disabled(model.updateInProgress)
                PermissionAccessSection(model: model)
                agentOverlapSection
                ApplicationUpdateSettingsSection(model: model.applicationUpdates)
                UpdateSettingsSection(model: model.updates)
                helperSection
                    .disabled(model.updateInProgress)
                generalSection
            }
            .formStyle(.grouped)
            .task {
                await model.loadProjectScanRoots()
                projectRootsDraft = model.projectScanRoots
                await model.loadPermissions()
            }
            .onChange(of: model.projectScanRoots) { projectRootsDraft = $0 }
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

    private var generalSection: some View {
        Section(L10n.text("通用")) {
            Picker(L10n.text("界面语言"), selection: Binding(
                get: { AppLanguage(rawValue: languagePreference) ?? .english },
                set: { languagePreference = $0.rawValue }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.nativeName).tag(language)
                }
            }
            if (AppLanguage(rawValue: languagePreference) ?? .english) != L10n.language {
                Label(L10n.text("重启应用后生效。"), systemImage: "arrow.clockwise")
                    .font(.caption).foregroundColor(.orange)
            }
            LabeledContent(L10n.text("应用版本"), value: "\(AppVersion.current.version) (\(AppVersion.current.build))")
        }
    }

    private var projectRootsHaveChanges: Bool {
        Set(projectRootsDraft.map(\.standardizedFileURL)) != Set(model.projectScanRoots.map(\.standardizedFileURL))
    }

    private var projectScanRootsSection: some View {
        Section(L10n.text("项目扫描目录")) {
            Toggle(L10n.text("默认勾选项目产物"), isOn: Binding(
                get: { model.preselectProjectArtifacts },
                set: { model.updateProjectArtifactPreselection($0) }
            ))
            .help(L10n.text("含 Git 跟踪项，仅勾选通过安全检查的产物。"))
            HStack {
                Text(L10n.text("{0} 个扫描目录", String(projectRootsDraft.count)))
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button(L10n.text("添加目录…")) { addProjectScanRoots() }
            }
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    if projectRootsDraft.isEmpty {
                        Text(L10n.text("尚未配置项目扫描目录"))
                            .foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 132)
                    }
                    ForEach(projectRootsDraft, id: \.self) { root in
                        HStack(spacing: 10) {
                            Image(systemName: "folder").foregroundColor(.secondary)
                            Text(root.path).font(.caption.monospaced()).textSelection(.enabled)
                                .lineLimit(1).truncationMode(.middle).help(root.path)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(L10n.text("移除")) { projectRootsDraft.removeAll { $0 == root } }
                                .buttonStyle(.borderless)
                                .help(L10n.text("仅移出扫描范围，不删除磁盘目录"))
                                .accessibilityLabel(L10n.text("移除扫描目录 {0}", root.path))
                        }
                        .frame(height: 44)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                }
            }
            .frame(height: 132)
            if projectRootsHaveChanges {
                HStack {
                    Button(L10n.text("保存扫描目录")) {
                        let roots = projectRootsDraft
                        Task { await model.saveProjectScanRoots(roots, startInitialScan: false) }
                    }
                    Button(L10n.text("撤销更改")) { projectRootsDraft = model.projectScanRoots }
                    Text(L10n.text("忙碌时保存，下次扫描生效。"))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if let error = model.projectScanRootsError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(.red)
                Button(L10n.text("重新读取目录配置")) { Task { await model.loadProjectScanRoots() } }
            }
        }
    }

    private func addProjectScanRoots() {
        guard let roots = model.selectProjectRootFolders() else { return }
        projectRootsDraft = Array(Set((projectRootsDraft + roots).map(\.standardizedFileURL)))
            .sorted { $0.path < $1.path }
    }

    private var agentOverlapSection: some View {
        Section(L10n.text("Agent 功能重叠分析")) {
            LabeledContent(L10n.text("本机模型状态"), value: model.agentOverlapStatus)
            if !model.agentOverlapSupportedPlatform {
                Text(L10n.text("Agent 能力分析需要 macOS 14 或更高版本及 Apple Silicon；其他功能可正常使用。"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Text(L10n.text("内置模型，本地分析 Skill 与 MCP。"))
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Picker(L10n.text("覆盖阈值"), selection: Binding(
                    get: { AgentOverlapThresholdOption.nearest(to: model.agentOverlapThreshold) },
                    set: { model.updateAgentOverlapThreshold($0.fraction) }
                )) {
                    ForEach(AgentOverlapThresholdOption.allCases, id: \.self) { option in
                        Text(verbatim: "\(option.rawValue)%").tag(option)
                    }
                }
                .pickerStyle(.menu)
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
            if model.agentContainmentRecalculationQueued {
                Text(L10n.text("已排队，当前任务完成后重新计算。"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Text(L10n.text("阈值用于预选，无需重新分析。"))
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
            Text(L10n.text("用于需要管理员权限的应用清理与恢复。"))
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
                Label(L10n.text("本次使用期间已授权"), systemImage: "lock.open")
                Button(L10n.text("立即关闭授权")) { helper.revokeSession() }.disabled(operationsBusy)
            } else {
                Button(L10n.text("验证连接并授权本次会话…")) { helper.authorizeSession() }
                    .disabled(helper.status != .enabled || helper.isChanging || operationsBusy)
            }
            if let message = helper.message { Text(message).font(.caption).textSelection(.enabled) }
            if helper.status == .unavailable || helper.status == .notFound {
                Text(L10n.text("当前构建无法启用 Helper。"))
                    .font(.caption).foregroundColor(.orange)
            }
        }
    }
}

extension PermissionsView {
    private var protectionSection: some View {
        Section(L10n.text("永久保护")) {
            Text(L10n.text("保护所选路径及其全部内容。"))
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
            Toggle(L10n.text("默认勾选大文件中的安装包"), isOn: Binding(
                get: { model.preselectLargeFileInstallers },
                set: { model.updateLargeFileInstallerPreselection($0) }
            ))
            .toggleStyle(.switch)
            .help(L10n.text("下次扫描生效。"))
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
            if model.defaultQuarantineRetentionPolicy == .immediate {
                Label(L10n.text("项目将移入系统废纸篓，可在清空废纸篓前恢复。"), systemImage: "trash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(L10n.text("仅影响新清理项目，已有恢复记录不变。"))
                    .font(.caption).foregroundColor(.secondary)
            }
            Toggle(L10n.text("关闭窗口或退出时提醒清空废纸篓"), isOn: Binding(
                get: { !suppressTrashReminder }, set: { suppressTrashReminder = !$0 }
            ))
            .help(L10n.text("手动清空废纸篓始终需要确认。"))
        }
    }

}

struct PermissionAccessSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section(L10n.text("权限")) {
            PermissionRow(
                icon: "folder.badge.questionmark",
                title: L10n.text("完全磁盘访问"),
                detail: L10n.text("扫描受限目录时需要。"),
                state: model.permissionSnapshot?.fullDiskAccess.status == .actionRequired
                    ? L10n.text("访问检查未通过") : permissionStateTitle(model.permissionSnapshot?.fullDiskAccess.status),
                stateColor: permissionStateColor(model.permissionSnapshot?.fullDiskAccess.status)
            ) {
                Button(L10n.text("打开系统设置…")) { model.openFullDiskAccessSettings() }
                    .controlSize(.small)
            }
            .help(model.permissionSnapshot?.fullDiskAccess.explanation ?? L10n.text("点击全扫描时检查权限"))
            PermissionRow(
                icon: "app.badge.checkmark",
                title: L10n.text("App 管理"),
                detail: L10n.text("卸载应用时按需授权。"),
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
