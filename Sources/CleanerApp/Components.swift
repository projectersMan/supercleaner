import CleanerCore
import SwiftUI

struct RiskBadge: View {
    let risk: RiskLevel
    var body: some View { Label(title, systemImage: icon).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).foregroundColor(color).background(color.opacity(0.12), in: Capsule()) }
    private var title: String { risk == .safe ? "低风险" : risk == .review ? "默认保留" : "始终保护" }
    private var icon: String { risk == .safe ? "checkmark.shield" : risk == .review ? "questionmark.circle" : "lock.fill" }
    private var color: Color { risk == .safe ? .green : risk == .review ? .orange : .secondary }
}

struct RecommendationBadge: View {
    let disposition: CleanupDisposition
    var body: some View {
        Label(disposition.displayTitle, systemImage: disposition.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundColor(disposition.color)
            .background(disposition.color.opacity(0.12), in: Capsule())
    }
}

struct CandidateRow: View {
    @ObservedObject var model: AppModel
    let candidate: CleanupCandidate
    var body: some View {
        HStack(spacing: 12) {
            Toggle(
                isOn: Binding(
                    get: { model.selectedIDs.contains(candidate.id) },
                    set: { _ in model.toggle(candidate) }
                )
            ) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(candidate.risk == .blocked)
                .accessibilityLabel(SelectionLabelPolicy.cleanupToggle(name: candidate.displayName, isSelected: model.selectedIDs.contains(candidate.id), isBlocked: candidate.risk == .blocked))
                .accessibilityHint(candidate.risk == .review ? "此项目默认保留；勾选会把它加入手动计划" : "")
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayName).fontWeight(.medium).lineLimit(1)
                Text("\(candidate.category.displayTitle) · \(candidate.evidence.first?.summary ?? candidate.url.deletingLastPathComponent().lastPathComponent)")
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Text(ByteCountFormatter.cleanerString(bytes: candidate.bytes)).foregroundColor(.secondary)
            RecommendationBadge(disposition: model.disposition(for: candidate))
        }
        .padding(.vertical, 7)
    }
}

struct CandidateInspector: View {
    let candidate: CleanupCandidate?
    let isSelected: Bool
    let disposition: CleanupDisposition?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("安全说明").font(.headline)
                if let candidate {
                    HStack { if let disposition { RecommendationBadge(disposition: disposition) }; Spacer(); Label(isSelected ? "已加入计划" : "已保留", systemImage: isSelected ? "checkmark.square.fill" : "square").foregroundColor(isSelected ? .accentColor : .secondary) }
                    Text(candidate.displayName).font(.title2.weight(.semibold))
                    Text(candidate.url.path).font(.caption.monospaced()).foregroundColor(.secondary).textSelection(.enabled)
                    CandidateSafetyDetails(candidate: candidate)
                } else {
                    Text("选择一个项目查看发现依据、风险判断、计划动作和恢复方式。")
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 300, idealWidth: 360)
    }
}

struct CandidateSafetyDetails: View {
    let candidate: CleanupCandidate

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .topLeading)], alignment: .leading, spacing: 10) {
            InspectorSection(title: "项目资料", icon: "doc.text.magnifyingglass") {
                InspectorFact(label: "类别", value: candidate.category.displayTitle)
                InspectorFact(label: "来源", value: candidate.source.displayTitle)
                InspectorFact(label: "大小", value: ByteCountFormatter.cleanerString(bytes: candidate.bytes))
                InspectorFact(label: "活跃状态", value: candidate.isActive ? "正在使用" : "扫描时未发现占用")
                if let date = candidate.lastAccessDate { InspectorFact(label: "最近访问", value: date.formatted(date: .abbreviated, time: .omitted)) }
            }
            InspectorSection(title: "为什么发现", icon: "magnifyingglass") {
                ForEach(candidate.evidence, id: \.self) { evidence in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(evidence.summary)
                        if let details = evidence.details { Text(details).font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
            InspectorSection(title: "风险判断", icon: candidate.risk == .blocked ? "lock.shield" : "shield.checkered") { Text(candidate.risk.explanation) }
            InspectorSection(title: "执行时会发生什么", icon: "shippingbox") { Text(candidate.plannedActionExplanation) }
            InspectorSection(title: "会保留什么", icon: "checkmark.shield") { Text(candidate.retentionExplanation) }
            InspectorSection(title: "如何恢复", icon: "arrow.uturn.backward.circle") { Text("从恢复记录恢复；若原路径已有文件，会恢复到相邻位置，绝不覆盖。") }
            InspectorSection(title: "执行前复验", icon: "checkmark.seal") { Text("重新检查路径、文件身份、活跃状态、规则版本和计划期限；任何变化都会安全跳过。") }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct CleanupCandidateCard: View {
    @ObservedObject var model: AppModel
    let candidate: CleanupCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CandidateRow(model: model, candidate: candidate)
            Text(candidate.url.path)
                .font(.caption.monospaced()).foregroundColor(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ReviewFilterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            TextField("搜索名称、路径或证据", text: $model.reviewQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
            Picker("建议", selection: $model.reviewDispositionFilter) {
                ForEach(ReviewDispositionFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            Toggle("仅显示已选", isOn: $model.showsSelectedOnly)
                .toggleStyle(.switch)
                .controlSize(.small)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) { content }
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct InspectorFact: View {
    let label: String
    let value: String
    var body: some View { HStack(alignment: .firstTextBaseline) { Text(label); Spacer(); Text(value).foregroundColor(.primary).multilineTextAlignment(.trailing) } }
}

private extension RiskLevel {
    var explanation: String {
        switch self {
        case .safe: "证据足以表明内容可重建，因此默认加入计划。"
        case .review: "内容可能有重建成本或上下文价值，因此系统默认保留；你仍可在自定义模式中加入计划。"
        case .blocked: "权限、活跃状态或资产类型不允许自动处理，此项目不会进入计划。"
        }
    }
}

private extension CandidateSource {
    var displayTitle: String {
        switch self {
        case .general: "通用扫描"
        case .agentWorkspace: "Agent 环境"
        case .application: "应用卸载"
        case .diskAnalysis: "磁盘分析"
        case .projectArtifacts: "项目产物"
        }
    }
}

extension CleanupCategory {
    var displayTitle: String {
        switch self {
        case .cache: "应用缓存"
        case .log: "日志"
        case .temporaryFile: "临时文件"
        case .installerArtifact: "安装产物"
        case .developerCache: "开发工具缓存"
        case .largeFile: "大文件"
        case .application: "应用程序"
        case .applicationSupport: "应用支持数据"
        case .agentSkill: "Agent Skill"
        case .agentMCP: "MCP"
        case .agentSession: "Agent 会话"
        case .agentSandbox: "Agent 沙箱"
        case .agentWorktree: "Git Worktree"
        case .agentModelCache: "模型缓存"
        case .agentPackageCache: "工具包缓存"
        case .agentUnknown: "未识别 Agent 资产"
        case .credential: "凭证"
        case .configuration: "配置"
        case .userKnowledge: "用户知识"
        }
    }
}

extension CleanupDisposition {
    var displayTitle: String {
        switch self {
        case .recommended: "低风险"
        case .deepClean: "可重建"
        case .retain: "建议保留"
        case .protected: "始终保护"
        }
    }

    var icon: String {
        switch self {
        case .recommended: "checkmark.shield"
        case .deepClean: "arrow.down.circle"
        case .retain: "archivebox"
        case .protected: "lock.fill"
        }
    }

    var color: Color {
        switch self {
        case .recommended: .green
        case .deepClean: .blue
        case .retain: .red
        case .protected: .secondary
        }
    }
}

private extension CleanupCandidate {
    var plannedActionExplanation: String {
        risk == .blocked ? "不会进入执行计划。" : "通过执行前复验后删除，可从恢复记录找回。"
    }

    var retentionExplanation: String {
        source == .agentWorkspace
            ? "保留 Skills、MCP 配置、Prompt、凭证、会话和代码；只处理计划中这一条路径。"
            : "只处理当前候选路径，不扩展到相邻目录或用户内容。"
    }
}

struct EmptyState: View {
    let title: String, message: String, icon: String
    var body: some View { VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 42)).foregroundColor(.secondary); Text(title).font(.title2.weight(.semibold)); Text(message).foregroundColor(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40) }
}

struct SelectionActionBar<Actions: View>: View {
    let hasSelection: Bool
    let title: String
    let detail: String
    let actions: Actions

    init(hasSelection: Bool, title: String, detail: String, @ViewBuilder actions: () -> Actions) {
        self.hasSelection = hasSelection
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: hasSelection ? "checklist.checked" : "checklist.unchecked")
                .font(.title3).foregroundColor(hasSelection ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            actions
        }
        .tint(Color.accentColor)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

struct DimensionActionBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Divider()
        if model.selection == .applications {
            applicationSelectionBar
        } else {
            candidateSelectionBar
        }
    }

    private var applicationSelectionBar: some View {
        let summary = model.uninstallBatchSummary
        return SelectionActionBar(
            hasSelection: summary.itemCount > 0,
            title: model.isCurrentModuleScanning
                ? "正在扫描应用卸载"
                : model.phase == .executing
                    ? "正在删除应用内容"
                    : summary.itemCount == 0
                        ? "尚未选择卸载内容"
                        : "已选 \(summary.applicationCount) 个应用 · \(summary.itemCount) 项",
            detail: model.isCurrentModuleScanning
                ? "正在扫描，报告就绪后可确认删除。"
                : model.phase == .executing
                    ? "正在删除 \(model.executionProgress.completed)/\(model.executionProgress.total)"
                    : summary.itemCount == 0
                        ? "当前没有已选项目。可手动勾选应用，或展开后逐项选择；扫描不会默认选中任何卸载项。"
                        : "约 \(ByteCountFormatter.cleanerString(bytes: summary.bytes))；删除后可在恢复记录中找回。"
        ) {
            if model.isCurrentModuleScanning {
                ProgressView().controlSize(.small)
                Button("取消扫描") { model.cancelScan() }
            } else if model.phase == .executing {
                ProgressView().controlSize(.small)
                Button("停止后续项目") { model.cancelExecution() }
            } else if summary.itemCount > 0 {
                Button("清空选择") { model.clearUninstallSelection() }
            }
            Button { model.executeUninstallBatch() } label: {
                Label("确认删除", systemImage: "trash.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isCurrentModuleScanning || model.phase == .executing || !model.canExecuteUninstallBatch)
        }
    }

    private var candidateSelectionBar: some View {
        let selected = model.selectedCandidates
        let bytes = selected.reduce(UInt64(0)) { $0 + $1.bytes }
        return SelectionActionBar(
            hasSelection: !selected.isEmpty,
            title: selected.isEmpty ? "尚未选择清理内容" : "已选 \(selected.count) 项",
            detail: detail(count: selected.count, bytes: bytes)
        ) {
            if model.isCurrentModuleScanning {
                ProgressView().controlSize(.small)
                Button("取消扫描") { model.cancelScan() }
                deleteButton.disabled(true)
            } else if model.phase == .executing {
                ProgressView().controlSize(.small)
                Button("停止后续项目") { model.cancelExecution() }
                deleteButton.disabled(true)
            } else {
                if !selected.isEmpty {
                    Button("清空选择") { model.clearCurrentSelection() }
                }
                deleteButton.disabled(selected.isEmpty || !model.hasCompletedScan || model.phase == .scanning || model.oneClickCleanupIsRunning)
            }
        }
    }

    private var deleteButton: some View {
        Button {
            model.requestExecution()
        } label: {
            Label("确认删除", systemImage: "trash.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func detail(count: Int, bytes: UInt64) -> String {
        if model.isCurrentModuleScanning { return "正在扫描，报告就绪后可确认删除。" }
        if model.phase == .executing {
            return "正在删除 \(model.executionProgress.completed)/\(model.executionProgress.total)"
        }
        if case .failed = model.phase, let message = model.statusMessage { return message }
        guard count > 0 else { return "勾选需要清理的项目，删除后可在恢复记录中找回。" }
        let hidden = model.hiddenSelectedCount
        let hiddenDetail = hidden > 0 ? "其中 \(hidden) 项被筛选隐藏；" : ""
        return "约 \(ByteCountFormatter.cleanerString(bytes: bytes))；\(hiddenDetail)删除后可在恢复记录中找回。"
    }
}

struct OneClickCleanupActionBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let defaults = model.defaultCleanupSelection
        let candidateCount = defaults?.systemCleanup.count ?? 0
        let bytes = defaults?.bytes ?? 0

        Divider()
        SelectionActionBar(
            hasSelection: model.canRunOneClickCleanup || model.oneClickCleanupIsRunning,
            title: title(candidateCount: candidateCount),
            detail: detail(candidateCount: candidateCount, bytes: bytes)
        ) {
            if model.oneClickCleanupIsRunning {
                ProgressView().controlSize(.small)
            }
            Button { model.runOneClickCleanup() } label: {
                Label(model.oneClickCleanupIsRunning ? "系统清理中" : "一键系统清理", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canRunOneClickCleanup)
            .accessibilityHint("仅处理系统清理中默认勾选的项目")
        }
    }

    private func title(candidateCount: Int) -> String {
        if model.oneClickCleanupIsRunning { return "正在执行系统清理" }
        guard model.hasScanResult(for: .general) else { return "等待系统清理扫描完成" }
        if candidateCount > 0 {
            return "系统清理已就绪 · 待清理 " + String(candidateCount) + " 项"
        }
        return "当前无需默认系统清理"
    }

    private func detail(candidateCount: Int, bytes: UInt64) -> String {
        if model.oneClickCleanupIsRunning {
            return "正在清理 " + String(model.executionProgress.completed) + "/" + String(model.executionProgress.total) + "；系统清理状态会同步更新。"
        }
        guard model.hasScanResult(for: .general) else { return "系统清理扫描完成后可处理默认勾选项。" }
        guard candidateCount > 0 else {
            return "应用、大文件和 Agent 环境可进入对应页面手动选择。"
        }
        return "约 " + ByteCountFormatter.cleanerString(bytes: bytes) + "；仅处理系统默认项，可从恢复记录找回。"
    }
}
