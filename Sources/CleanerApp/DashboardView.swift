import CleanerCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var hoveredResultModule: ScanModuleID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if model.phase == .scanning {
                    scanProgress
                    if model.hasCompletedScan { previousReportNotice }
                } else if model.systemReport != nil {
                    scanProgress
                } else {
                    scanCoverage
                    preScanTrust
                }
            }
            .padding(.horizontal, 34).padding(.vertical, 28)
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 26) {
            Image(systemName: model.phase == .scanning ? "internaldrive.badge.magnifyingglass" : "shield.lefthalf.filled")
                .font(.system(size: 54)).foregroundStyle(.tint).frame(width: 72)
            VStack(alignment: .leading, spacing: 9) {
                Text(heroTitle).font(.system(size: 34, weight: .semibold))
                Text(heroDetail).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                if model.phase == .scanning {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Button("取消扫描") { model.cancelScan() }
                    }
                    .padding(.top, 8)
                } else if model.systemReport != nil {
                    HStack(spacing: 14) {
                        Button("重新完整扫描") { model.startFullScan() }
                            .controlSize(.large)
                            .disabled(model.oneClickCleanupIsRunning)
                        if model.sessionCleanupSummary.itemCount > 0 {
                            Label(
                                "本次打开已清理 \(model.sessionCleanupSummary.itemCount) 项 · \(ByteCountFormatter.cleanerString(bytes: model.sessionCleanupSummary.bytes))",
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.callout.weight(.semibold))
                            .foregroundColor(.green)
                        }
                    }
                    .padding(.top, 8)
                } else {
                    Button { model.startFullScan() } label: {
                        Label("开始完整扫描", systemImage: "magnifyingglass")
                            .font(.headline).padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
                    .accessibilityHint("只读扫描系统清理、应用、大文件和 Agent 环境")
                }
            }
            Spacer()
        }
        .padding(.vertical, 14)
    }

    private var heroTitle: String {
        if model.phase == .scanning { return "正在扫描整个支持范围" }
        return model.systemReport != nil ? "清理中心" : "先完整扫描，再决定清理什么"
    }

    private var heroDetail: String {
        if model.phase == .scanning {
            return "四个模块共享同一次扫描版本。此过程默认只读取文件元数据；在 Agent 环境中会受限读取 `SKILL.md` 头部内容用于建立目录索引，不会清理或上传任何数据。"
        }
        if model.systemReport != nil {
            return "系统清理扫描完成后即可一键处理默认勾选项；应用、大文件和 Agent 环境请进入对应页面手动选择。"
        }
        return "扫描所有受支持且可安全访问的位置，统一生成系统清理、应用、大文件和 Agent 环境报告。扫描过程零写入。"
    }

    private var scanCoverage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一次扫描包含").font(.title2.bold())
            VStack(spacing: 0) {
                ScanScopeRow(icon: "trash", title: "系统清理", detail: "缓存、日志、临时文件、安装包、开发缓存", color: .green)
                Divider()
                ScanScopeRow(icon: "app.dashed", title: "应用卸载", detail: "以 App 为单位，展开应用本体与精确关联项", color: .blue)
                Divider()
                ScanScopeRow(icon: "doc.text.magnifyingglass", title: "大文件", detail: "按目录展开具体文件，不按体积自动清理", color: .orange)
                Divider()
                ScanScopeRow(icon: "terminal", title: "Agent 环境", detail: "按真实目录和 Skill 标记动态组织，再逐条决定删或不删", color: .purple)
            }
            .padding(.horizontal, 8)
            Label("扫描受支持的位置，不声称遍历启动磁盘的每一个字节", systemImage: "info.circle")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var scanProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("维度状态").font(.title2.bold())
                Spacer()
                if let defaults = model.defaultCleanupSelection {
                    Text("待系统清理 \(defaults.systemCleanup.count) 项 · \(ByteCountFormatter.cleanerString(bytes: defaults.bytes))")
                        .font(.callout).foregroundColor(.secondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(ScanModuleID.allCases, id: \.self) { module in
                    let status = model.scanProgressByModule[module] ?? ScanModuleStatus(module: module, state: .waiting)
                    moduleStatusRow(module: module, status: status)
                    Divider()
                }
            }
            .padding(.horizontal, 16)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var previousReportNotice: some View {
        Label("新扫描完成前，上一次完整报告仍被安全保留。", systemImage: "clock.arrow.circlepath")
            .font(.callout).foregroundColor(.secondary).padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private var preScanTrust: some View {
        HStack(spacing: 14) {
            TrustItem(icon: "eye", title: "扫描可解释", detail: "每项都显示路径和发现依据")
            TrustItem(icon: "play.circle", title: "删除前检查", detail: "自动复验，跳过变化或占用项")
            TrustItem(icon: "arrow.uturn.backward.circle", title: "默认可恢复", detail: "删除后可恢复，恢复不覆盖原文件")
        }
    }

    @ViewBuilder private func moduleStatusRow(
        module: ScanModuleID,
        status: ScanModuleStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if model.hasScanResult(for: module) {
                    Button {
                        model.openScanResult(module)
                    } label: {
                        moduleStatusHeader(module: module, status: status, showsChevron: true)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("打开\(module.resultDestinationTitle)扫描结果")
                } else {
                    moduleStatusHeader(module: module, status: status, showsChevron: false)
                }
            }
            .padding(.vertical, 6)
            .background(
                hoveredResultModule == module && model.hasScanResult(for: module)
                    ? module.color.opacity(0.09)
                    : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .onHover { isHovering in
                hoveredResultModule = isHovering && model.hasScanResult(for: module) ? module : nil
            }
            let failures = model.cleanupFailures(for: module)
            if !failures.isEmpty {
                moduleFailureList(failures)
            }
        }
        .padding(.vertical, 12)
    }

    private func moduleFailureList(_ failures: [DefaultCleanupFailure]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(failures) { failure in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: failure.isRetryable ? "arrow.clockwise.circle" : "exclamationmark.triangle")
                        .foregroundColor(failure.isRetryable ? .orange : .secondary)
                    Text(failure.candidate.displayName).fontWeight(.medium).lineLimit(1)
                    Text(failure.reason).foregroundColor(.secondary).lineLimit(2)
                    Spacer()
                    Text(
                        failure.isRetryable
                            ? model.phase == .scanning ? "扫描完成后可重试" : "可安全重试"
                            : "需重新扫描"
                    )
                    .foregroundColor(failure.isRetryable ? .orange : .secondary)
                }
                .font(.caption)
            }
            let retryable = failures.filter(\.isRetryable)
            if !retryable.isEmpty {
                Button(
                    model.phase == .scanning
                        ? "扫描完成后可重试 \(retryable.count) 项"
                        : "安全重试 \(retryable.count) 项"
                ) {
                    model.retryCleanupFailures(retryable)
                }
                .controlSize(.small)
                .disabled(model.phase == .scanning || model.phase == .executing || model.oneClickCleanupIsRunning)
            }
        }
        .padding(.leading, 44)
        .padding(.trailing, 8)
    }

    private func moduleStatusHeader(
        module: ScanModuleID,
        status: ScanModuleStatus,
        showsChevron: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: module.icon).foregroundColor(module.color).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).fontWeight(.medium)
                if module == .general {
                    if let message = status.message {
                        Text(message).font(.caption).foregroundColor(.secondary)
                    }
                    ForEach(status.limitations) { limitation in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(limitation.title).font(.caption.weight(.semibold))
                            if let path = limitation.path {
                                Text(path.path).font(.caption2).foregroundColor(.secondary)
                            }
                            Text(limitation.impact).font(.caption2).foregroundColor(.secondary)
                            Text(limitation.recovery).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    if let cleanupStatus = model.oneClickStatus(for: module) {
                        Text(cleanupStatus)
                            .font(.caption)
                            .fontWeight(model.hasCleanupFailures(for: module) ? .semibold : .regular)
                            .foregroundColor(
                                model.oneClickActiveModules.contains(module)
                                    ? .blue
                                    : model.hasCleanupFailures(for: module) ? .orange : .secondary
                            )
                    }
                } else if model.hasScanResult(for: module), let detail = model.scanDiscoverySummary?.detail(for: module) {
                    Text(detail).font(.caption).foregroundColor(.secondary)
                } else if status.state == .failed, let message = status.message {
                    Text(message).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            moduleCleanupState(module: module, status: status)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private func moduleCleanupState(
        module: ScanModuleID,
        status: ScanModuleStatus
    ) -> some View {
        if model.hasScanResult(for: module) {
            if model.oneClickActiveModules.contains(module) || model.activeCleanupModules.contains(module) {
                Label("正在清理", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.tint)
            } else if model.cleanedModules.contains(module) {
                Label("已清理", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if model.hasDiscoveredContent(for: module) {
                Text("立即清理").foregroundStyle(.tint)
            } else {
                Label("无需清理", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        } else {
            ScanModuleStateView(state: status.state)
        }
    }
}

private struct ScanScopeRow: View {
    let icon: String, title: String, detail: String
    let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundColor(color).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScanModuleStateView: View {
    let state: ScanModuleState
    var body: some View {
        Group {
            if state == .scanning { HStack(spacing: 7) { ProgressView().controlSize(.small); Text("扫描中") } }
            else { Label(state.title, systemImage: state.icon) }
        }
        .font(.caption.weight(.semibold)).foregroundColor(state.color)
    }
}

private struct TrustItem: View {
    let icon: String, title: String, detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension ScanModuleID {
    var title: String {
        switch self { case .general: "系统清理"; case .applications: "应用"; case .largeFiles: "大文件"; case .agentEnvironment: "Agent 环境" }
    }
    var icon: String {
        switch self { case .general: "trash"; case .applications: "app.dashed"; case .largeFiles: "doc.text.magnifyingglass"; case .agentEnvironment: "terminal" }
    }
    var color: Color {
        switch self { case .general: .green; case .applications: .blue; case .largeFiles: .orange; case .agentEnvironment: .purple }
    }
    var resultDestinationTitle: String {
        switch self { case .general: "系统清理"; case .applications: "应用卸载"; case .largeFiles: "大文件"; case .agentEnvironment: "Agent 环境" }
    }
}

private extension ScanModuleState {
    var title: String {
        switch self { case .waiting: "等待"; case .scanning: "扫描中"; case .completed, .limited: "扫描完成"; case .failed: "失败"; case .cancelled: "已取消" }
    }
    var icon: String {
        switch self { case .waiting: "clock"; case .scanning: "magnifyingglass"; case .completed, .limited: "checkmark.circle.fill"; case .failed: "xmark.circle.fill"; case .cancelled: "stop.circle" }
    }
    var color: Color {
        switch self { case .waiting: .secondary; case .scanning: .accentColor; case .completed, .limited: .green; case .failed: .red; case .cancelled: .secondary }
    }
}
