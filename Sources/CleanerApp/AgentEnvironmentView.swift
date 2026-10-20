import CleanerCore
import SwiftUI

struct AgentEnvironmentView: View {
    @ObservedObject var model: AppModel
    @State private var selectedSection: AgentEnvironmentSection = .skills

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.hasScanResult(for: .agentEnvironment) {
                ScanRequiredView(destinationTitle: "Agent 环境") { model.navigateToScan() }
            } else {
                filterBar
                ZStack {
                    skillsContent
                        .opacity(selectedSection == .skills ? 1 : 0)
                        .allowsHitTesting(selectedSection == .skills)
                        .accessibilityHidden(selectedSection != .skills)
                    mcpContent
                        .opacity(selectedSection == .mcp ? 1 : 0)
                        .allowsHitTesting(selectedSection == .mcp)
                        .accessibilityHidden(selectedSection != .mcp)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent 环境")
                    .font(.largeTitle.bold())
                Text("按平台呈现本机 Agent 的 Skill 与 MCP 配置。官方路径由独立规则表维护，项目目录会识别 Codex 与 Claude 的仓库级资源；MCP 仅提取服务器名称和传输方式，不保存或展示密钥、环境变量与请求头。Skill 和 MCP 默认保留，不会自动清理。")
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(24)
    }

    private var filterBar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Text("类型").foregroundColor(.secondary)
                Picker("类型", selection: $selectedSection) {
                    ForEach(AgentEnvironmentSection.allCases, id: \.self) { section in
                        Text(section.displayTitle).tag(section)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            Divider().frame(height: 24)

            HStack(spacing: 8) {
                Text("平台").foregroundColor(.secondary)
                Picker("平台", selection: Binding(
                    get: { model.agentProviderFilter },
                    set: { model.selectAgentProvider($0) }
                )) {
                    Text("全部平台").tag(Optional<AgentProvider>.none)
                    ForEach(model.detectedAgentProviders, id: \.self) { provider in
                        Text(provider.displayTitle).tag(Optional(provider))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170)
            }

            Divider().frame(height: 24)

            HStack(spacing: 8) {
                Text("显示").foregroundColor(.secondary)
                Picker("显示范围", selection: $model.agentItemsSelectionFilter) {
                    ForEach(AgentItemsSelectionFilter.allCases, id: \.self) { filter in
                        Text(filter.displayTitle).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder private var mcpContent: some View {
        VStack(spacing: 0) {
            mcpToolbar
            if model.visibleAgentMCPConfigurations.isEmpty {
                EmptyState(
                    title: model.agentItemsSelectionFilter == .selected ? "没有已选中的 MCP 配置" : "没有 MCP 配置",
                    message: "未发现符合条件的 MCP 配置。",
                    icon: "network"
                )
            } else {
                List {
                    ForEach(model.visibleAgentMCPConfigurations) { configuration in
                        MCPConfigurationRow(
                            model: model,
                            configuration: configuration,
                            candidate: model.agentMCPCandidate(for: configuration)
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var mcpToolbar: some View {
        HStack {
            Text("共 \(model.agentMCPConfigurations.count) 个配置文件")
            Text("\(model.agentMCPConfigurations.reduce(0) { $0 + $1.servers.count }) 个服务器定义")
            Spacer()
            Label("敏感字段不提取、不保存、不展示", systemImage: "lock.shield")
                .foregroundColor(.purple)
        }
        .font(.callout)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    @ViewBuilder private var skillsContent: some View {
        VStack(spacing: 0) {
            skillsToolbar
            if model.visibleAgentSkillSections.isEmpty {
                EmptyState(
                    title: model.agentItemsSelectionFilter == .selected ? "没有已选中的 Skill" : "没有 Skill",
                    message: "未发现符合条件的 Skill。",
                    icon: "square.stack.3d.up"
                )
            } else {
                List {
                    ForEach(model.visibleAgentSkillSections) { section in
                        Section {
                            ForEach(section.skills) { binding in
                                AgentSkillRow(model: model, binding: binding)
                            }
                        } header: {
                            HStack {
                                Label(section.group.title, systemImage: section.group.icon)
                                Spacer()
                                Text("\(section.skillCount) 个 Skill")
                                Text(ByteCountFormatter.cleanerString(bytes: section.reclaimableBytes))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var skillsToolbar: some View {
        HStack {
            Text("共 \(model.agentSkills.count) 个 Skill")
            if model.agentSkillDuplicatesCollapsedCount > 0 {
                Text("已折叠 \(model.agentSkillDuplicatesCollapsedCount) 个重复发现")
            }
            let plannedCount = model.visibleAgentSkillBindings.filter { $0.decision == .plannedForDeletion }.count
            if plannedCount > 0 {
                Text("其中 \(plannedCount) 个已加入删除计划")
            }
            Spacer()
        }
        .font(.callout)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

}

private struct MCPConfigurationRow: View {
    @ObservedObject var model: AppModel
    let configuration: MCPConfigurationRecord
    let candidate: CleanupCandidate?
    private var isSelected: Bool { candidate.map { model.selectedIDs.contains($0.id) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                mcpSelectionControl
                Image(systemName: "network")
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text(configuration.sourceLabel)
                        .font(.headline)
                    Text(configuration.fileURL.lastPathComponent)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                Spacer()
                SkillMetadataBadge(
                    title: "\(configuration.servers.count) 个服务器",
                    color: configuration.servers.isEmpty ? .secondary : .blue
                )
            }
            HStack(spacing: 8) {
                SkillMetadataBadge(title: configuration.provider.displayTitle, color: .purple)
                SkillMetadataBadge(title: configuration.scope.displayTitle, color: .blue)
                SkillMetadataBadge(title: configuration.parseStatus.displayTitle, color: configuration.parseStatus.color)
            }
            Text(configuration.fileURL.path)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
    }

    @ViewBuilder private var mcpSelectionControl: some View {
        if let candidate {
            Toggle(isOn: Binding(
                get: { model.selectedIDs.contains(candidate.id) },
                set: { _ in model.toggle(candidate) }
            )) { EmptyView() }
            .toggleStyle(.checkbox)
            .tint(Color.accentColor)
            .labelsHidden()
            .disabled(!candidate.risk.isSelectable)
            .accessibilityLabel(SelectionLabelPolicy.cleanupToggle(
                name: configuration.fileURL.lastPathComponent,
                isSelected: isSelected,
                isBlocked: !candidate.risk.isSelectable
            ))
            .help(candidate.risk.isSelectable
                ? (isSelected ? "从删除计划移除 MCP 配置" : "将 MCP 配置加入删除计划；配置会移入隔离区，可从恢复记录找回")
                : "此 MCP 配置当前不可删除：路径受保护或无法验证")
        } else {
            Toggle(isOn: .constant(false)) { EmptyView() }
                .toggleStyle(.checkbox)
                .tint(Color.accentColor)
                .labelsHidden()
                .disabled(true)
                .help("无法验证此 MCP 配置，暂不能加入删除计划")
        }
    }
}

private struct AgentSkillRow: View {
    @ObservedObject var model: AppModel
    let binding: AgentSkillCleanupBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { binding.decision == .plannedForDeletion },
                    set: { shouldDelete in
                        model.setAgentSkillDecision(shouldDelete ? .plannedForDeletion : .retain, skillID: binding.id)
                    }
                )) { EmptyView() }
                .toggleStyle(.checkbox)
                .tint(Color.accentColor)
                .labelsHidden()
                .disabled(!binding.isDeletionAvailable)
                .accessibilityLabel(SelectionLabelPolicy.cleanupToggle(
                    name: binding.skill.displayName,
                    isSelected: binding.decision == .plannedForDeletion,
                    isBlocked: !binding.isDeletionAvailable
                ))
                .help(binding.isDeletionAvailable
                    ? (binding.decision == .plannedForDeletion ? "从删除计划移除" : "加入删除计划")
                    : binding.decisionReason)
                VStack(alignment: .leading, spacing: 4) {
                    Text(binding.skill.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    if let summary = binding.skill.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            HStack(spacing: 8) {
                SkillMetadataBadge(title: binding.skill.scope.displayTitle, color: .blue)
                SkillMetadataBadge(title: binding.skill.source.displayTitle, color: binding.skill.source.color)
                SkillMetadataBadge(title: binding.skill.kind.displayTitle, color: binding.skill.kind.color)
                SkillMetadataBadge(title: binding.skill.parseStatus.displayTitle, color: .orange)
            }
            if !binding.skill.tags.isEmpty {
                SkillTagCloud(values: Array(binding.skill.tags.prefix(4)))
            }
            Text(binding.skill.skillRootURL.path)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Text("关联 \(binding.linkedAssets.count) 个目录单元")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("可释放 \(ByteCountFormatter.cleanerString(bytes: binding.reclaimableBytes))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            if !binding.isDeletionAvailable {
                Text(binding.decisionReason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(binding.decision == .plannedForDeletion ? Color.accentColor.opacity(0.10) : Color.clear)
    }
}

private struct AgentSkillDetailPanel: View {
    @ObservedObject var model: AppModel
    let binding: AgentSkillCleanupBinding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(binding.skill.displayName)
                            .font(.title2.bold())
                        if let summary = binding.skill.summary, !summary.isEmpty {
                            Text(summary)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    SkillMetadataBadge(title: binding.group.title, color: .purple)
                }
                GroupBox("删除决策") {
                    VStack(alignment: .leading, spacing: 10) {
                        SkillDecisionControl(
                            decision: binding.decision,
                            isDeletionAvailable: binding.isDeletionAvailable,
                            reason: binding.decisionReason,
                            retainAction: { model.setAgentSkillDecision(.retain, skillID: binding.id) },
                            deleteAction: { model.setAgentSkillDecision(.plannedForDeletion, skillID: binding.id) }
                        )
                        Text("该操作只会把此 Skill 关联且当前允许删除的目录单元加入计划，不会绕过保护规则。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                GroupBox("基础信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("一级目录", binding.group.title)
                        detailRow("Provider", binding.skill.provider.displayTitle)
                        detailRow("范围", binding.skill.scope.displayTitle)
                        detailRow("来源", binding.skill.source.displayTitle)
                        detailRow("类型", binding.skill.kind.displayTitle)
                        detailRow("解析状态", binding.skill.parseStatus.displayTitle)
                        detailRow("关联单元", "\(binding.linkedAssets.count) 个")
                        detailRow("可删大小", ByteCountFormatter.cleanerString(bytes: binding.reclaimableBytes))
                    }
                }
                if !binding.skill.tags.isEmpty {
                    GroupBox("标签") { SkillTagCloud(values: binding.skill.tags) }
                }
                if !binding.skill.triggers.isEmpty {
                    GroupBox("触发词") { SkillTagCloud(values: binding.skill.triggers) }
                }
                if !binding.skill.tools.isEmpty {
                    GroupBox("工具") { SkillTagCloud(values: binding.skill.tools) }
                }
                GroupBox("路径") {
                    VStack(alignment: .leading, spacing: 8) {
                        detailPath("Skill 根目录", binding.skill.skillRootURL.path)
                        if let manifestURL = binding.skill.manifestURL {
                            detailPath("Manifest", manifestURL.path)
                        }
                    }
                }
                GroupBox("关联目录单元") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(binding.linkedAssets.prefix(12)) { asset in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(asset.candidate.displayName)
                                    .font(.callout.weight(.medium))
                                Text(asset.cleanupUnitURL.path)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                Text("\(asset.resourceKind.displayTitle) · \(asset.cleanupEligibility.displayTitle)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if binding.linkedAssets.count > 12 {
                            Text("其余 \(binding.linkedAssets.count - 12) 个目录单元未展开。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                HStack(spacing: 12) {
                    Button("在 Finder 中显示目录") {
                        model.openAgentSkillRoot(binding.skill)
                    }
                    if binding.skill.manifestURL != nil {
                        Button("打开 Manifest") {
                            model.openAgentSkillManifest(binding.skill)
                        }
                    }
                    Spacer()
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }

    private func detailPath(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SkillDecisionControl: View {
    let decision: AgentSkillDecision
    let isDeletionAvailable: Bool
    let reason: String
    let retainAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                Button("保留", action: retainAction)
                    .buttonStyle(.borderedProminent)
                    .tint(decision == .retain ? .secondary : .gray.opacity(0.4))
                Button("加入删除计划", action: deleteAction)
                    .buttonStyle(.borderedProminent)
                    .tint(decision == .plannedForDeletion ? .red : .gray.opacity(0.4))
                    .disabled(!isDeletionAvailable)
            }
            Text(reason)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SkillMetadataBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct SkillTagCloud: View {
    let values: [String]

    var body: some View {
        FlowLayout(values: values) { value in
            Text(value)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: Capsule())
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let values: [String]
    let content: (String) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunked(values, size: 4), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { value in
                        content(value)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunked(_ values: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [values] }
        var rows: [[String]] = []
        var currentIndex = 0
        while currentIndex < values.count {
            let nextIndex = min(currentIndex + size, values.count)
            rows.append(Array(values[currentIndex..<nextIndex]))
            currentIndex = nextIndex
        }
        return rows
    }
}

private struct AgentAssetRow: View {
    @ObservedObject var model: AppModel
    let asset: AgentAssetRecord
    private var selectable: Bool {
        asset.candidate.risk.isSelectable && asset.activity != .active && [.recommended, .deep].contains(asset.cleanupEligibility)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if selectable {
                    Toggle(isOn: Binding(get: { model.selectedIDs.contains(asset.id) }, set: { _ in model.toggle(asset.candidate) })) { EmptyView() }
                        .toggleStyle(.checkbox).labelsHidden()
                        .accessibilityLabel(SelectionLabelPolicy.cleanupToggle(name: asset.candidate.displayName, isSelected: model.selectedIDs.contains(asset.id), isBlocked: false))
                } else {
                    Image(systemName: asset.activity == .active ? "bolt.fill" : "lock.fill")
                        .foregroundColor(asset.activity == .active ? .orange : .secondary).frame(width: 14)
                }
                Text(asset.candidate.displayName).font(.headline).lineLimit(2)
                Spacer()
                AgentEligibilityBadge(eligibility: asset.cleanupEligibility, activity: asset.activity)
                Text(ByteCountFormatter.cleanerString(bytes: asset.candidate.bytes)).foregroundColor(.secondary)
            }
            Text(asset.candidate.url.path)
                .font(.caption.monospaced()).foregroundColor(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            AgentAssetDetails(asset: asset, isSelected: model.selectedIDs.contains(asset.id))
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(model.focusedCandidateID == asset.id ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .onTapGesture { model.focus(asset.id, for: .agentEnvironment) }
        .accessibilityAddTraits(model.focusedCandidateID == asset.id ? .isSelected : [])
    }
}

private struct AgentAssetDetails: View {
    let asset: AgentAssetRecord
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { metadata }
                VStack(alignment: .leading, spacing: 6) { metadata }
            }
            .font(.caption).foregroundColor(.secondary)
            Text("清理单元：\(asset.cleanupUnitURL.path)")
                .font(.caption.monospaced()).foregroundColor(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Label(isSelected ? "已加入当前计划" : "当前保持保留", systemImage: isSelected ? "checkmark.square.fill" : "square")
                .font(.caption).foregroundColor(isSelected ? .accentColor : .secondary)
            if !asset.candidate.evidence.isEmpty {
                Text(asset.candidate.evidence.map(\.summary).joined(separator: "\n"))
                    .font(.callout).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Skills、MCP、凭证、提示词、知识、源码、配置、活跃会话和 Worktree 不会被此清理单元扩展包含。", systemImage: "lock.shield")
                .font(.caption).foregroundColor(.purple)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var metadata: some View {
        Text("平台：\(asset.provider.displayTitle)")
        Text("范围：\(asset.scope.displayTitle)")
        Text("资源类型：\(asset.resourceKind.displayTitle)")
        Text("活动状态：\(asset.activity.displayTitle)")
        Text("清理资格：\(asset.cleanupEligibility.displayTitle)")
    }
}

private struct AgentCoverageBadge: View {
    let state: AgentProviderCoverageState

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .help(helpText)
    }

    private var title: String {
        switch state {
        case .notDetected: "未检测到"
        case .complete: "扫描完整"
        case .limited: "结果受限"
        case .unavailable: "无法访问"
        }
    }

    private var color: Color {
        switch state {
        case .complete: .green
        case .limited: .orange
        case .unavailable: .red
        case .notDetected: .secondary
        }
    }

    private var helpText: String {
        switch state {
        case .notDetected: "本轮未发现此平台的已知根目录"
        case .complete: "已完成此平台已发现根目录的统计"
        case .limited: "扫描预算用尽，当前结果不是完整总量"
        case .unavailable: "已发现根目录，但当前权限不足，无法完成读取"
        }
    }
}

private struct AgentEligibilityBadge: View {
    let eligibility: AgentCleanupEligibility
    let activity: AgentActivity
    var body: some View {
        Text(activity == .active ? "运行中" : eligibility.displayTitle)
            .font(.caption.weight(.semibold)).foregroundColor(activity == .active ? .orange : eligibility.color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((activity == .active ? Color.orange : eligibility.color).opacity(0.12), in: Capsule())
    }
}

private extension SelectionTriState {
    var icon: String { switch self { case .none: "square"; case .partial: "minus.square.fill"; case .all: "checkmark.square.fill" } }
    var accessibilityTitle: String { switch self { case .none: "未选择"; case .partial: "部分选择"; case .all: "全部选择" } }
}

private extension AgentProvider {
    var displayTitle: String { switch self { case .codex: "Codex"; case .claude: "Claude Code"; case .cursor: "Cursor"; case .trae: "Trae"; case .genericMCP: "通用 MCP"; case .git: "Git Worktree"; case .shared: "共享 / Global" } }
    var icon: String { switch self { case .codex: "chevron.left.forwardslash.chevron.right"; case .claude: "text.bubble"; case .cursor: "cursorarrow"; case .trae: "bolt"; case .genericMCP: "point.3.connected.trianglepath.dotted"; case .git: "arrow.triangle.branch"; case .shared: "globe" } }
}

private extension AgentScope {
    var displayTitle: String { switch self { case .global: "用户级"; case .project: "项目级"; case .shared: "共享 / 管理员级" } }
    var icon: String { switch self { case .global: "globe"; case .project: "folder"; case .shared: "person.2" } }
}

private extension AgentResourceKind {
    var displayTitle: String {
        switch self {
        case .runtimeTemporaryOutput: "运行时临时输出"; case .completedTaskCache: "已完成任务缓存"; case .buildCache: "构建缓存"; case .packageCache: "包缓存"; case .modelCache: "模型缓存"; case .sessionHistory: "会话 / 历史"; case .sandboxWorkspace: "沙箱 / 工作区"; case .skill: "Skill"; case .mcpDefinition: "MCP 定义"; case .configuration: "配置"; case .credential: "凭证"; case .promptKnowledge: "Prompt / 知识"; case .sourceCode: "源代码"; case .gitWorktree: "Git Worktree"; case .unknown: "未识别资产"
        }
    }
}

private extension AgentActivity {
    var displayTitle: String { switch self { case .active: "运行中"; case .recent: "最近使用"; case .completed: "已完成"; case .unknown: "未知" } }
}

private extension AgentCleanupEligibility {
    var displayTitle: String { switch self { case .recommended: "建议清理"; case .deep: "深度候选"; case .retained: "默认保留"; case .protected: "始终保护" } }
    var color: Color { switch self { case .recommended: .green; case .deep: .blue; case .retained: .orange; case .protected: .secondary } }
}

private extension SkillCatalogSource {
    var displayTitle: String {
        switch self {
        case .builtin: "内置"
        case .plugin: "插件"
        case .userInstalled: "用户安装"
        case .shared: "共享"
        case .extensionSupport: "扩展"
        case .project: "项目"
        case .unknown: "未知"
        }
    }

    var color: Color {
        switch self {
        case .builtin: .purple
        case .plugin: .blue
        case .userInstalled: .green
        case .shared: .orange
        case .extensionSupport: .secondary
        case .project: .mint
        case .unknown: .secondary
        }
    }
}

private extension SkillCatalogKind {
    var displayTitle: String {
        switch self {
        case .workflow: "工作流"
        case .designLibrary: "设计库"
        case .extensionSupport: "扩展辅助"
        case .projectSkill: "项目 Skill"
        case .unknown: "未知"
        }
    }

    var color: Color {
        switch self {
        case .workflow: .purple
        case .designLibrary: .pink
        case .extensionSupport: .blue
        case .projectSkill: .mint
        case .unknown: .secondary
        }
    }
}

private extension SkillMetadataParseStatus {
    var displayTitle: String {
        switch self {
        case .manifestParsed: "Manifest 解析"
        case .headingFallback: "标题回退"
        case .pathFallback: "路径回退"
        }
    }
}

private extension AgentSkillDecision {
    var color: Color {
        switch self {
        case .retain: .secondary
        case .plannedForDeletion: .red
        case .deletionUnavailable: .orange
        }
    }
}

private extension MCPConfigurationParseStatus {
    var displayTitle: String {
        switch self {
        case .parsed: "已解析"
        case .noServers: "无服务器定义"
        case .unreadable: "不可读取"
        case .malformed: "格式异常"
        }
    }

    var color: Color {
        switch self {
        case .parsed: .green
        case .noServers: .secondary
        case .unreadable, .malformed: .orange
        }
    }
}

private extension MCPTransportKind {
    var displayTitle: String {
        switch self {
        case .stdio: "stdio"
        case .http: "HTTP"
        case .sse: "SSE"
        case .webSocket: "WebSocket"
        case .sdk: "SDK"
        case .unknown: "未标注"
        }
    }
}
