import CleanerCore
import SwiftUI

struct RiskBadge: View {
    let risk: RiskLevel
    var body: some View { Label(title, systemImage: icon).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 4).foregroundColor(color).background(color.opacity(0.12), in: Capsule()) }
    private var title: String { risk == .safe ? L10n.text("低风险") : risk == .review ? L10n.text("默认保留") : L10n.text("始终保护") }
    private var icon: String { risk == .safe ? "checkmark.shield" : risk == .review ? "questionmark.circle" : "lock.fill" }
    private var color: Color { risk == .safe ? .green : risk == .review ? .orange : .secondary }
}

struct RecommendationBadge: View {
    let disposition: CleanupDisposition
    var candidate: CleanupCandidate? = nil
    private var title: String {
        if disposition == .protected, candidate?.evidence.contains(where: { $0.code.hasPrefix("scan-incomplete-") }) == true {
            return L10n.text("扫描未完成")
        }
        if disposition == .retain, candidate?.source == .historicalApplicationResidue { return L10n.text("可手动清理") }
        return disposition.displayTitle
    }
    var body: some View {
        Label(title, systemImage: disposition.icon)
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
    var showsRecommendationBadge = true
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
                .accessibilityHint(model.disposition(for: candidate) == .retain ? L10n.text("此项目默认保留；勾选会把它加入手动计划") : "")
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayName).fontWeight(.medium).lineLimit(1)
                Text("\(candidate.category.displayTitle) · \(candidate.evidence.first?.summary ?? candidate.url.deletingLastPathComponent().lastPathComponent)")
                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Text(candidate.hasIncompleteScan ? L10n.text("容量未确认") : ByteCountFormatter.cleanerString(bytes: candidate.bytes)).foregroundColor(.secondary)
            if showsRecommendationBadge {
                RecommendationBadge(disposition: model.disposition(for: candidate), candidate: candidate)
            }
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
                Text(L10n.text("安全说明")).font(.headline)
                if let candidate {
                    HStack { if let disposition { RecommendationBadge(disposition: disposition, candidate: candidate) }; Spacer(); Label(isSelected ? L10n.text("已加入计划") : L10n.text("已保留"), systemImage: isSelected ? "checkmark.square.fill" : "square").foregroundColor(isSelected ? .accentColor : .secondary) }
                    Text(candidate.displayName).font(.title2.weight(.semibold))
                    Text(candidate.url.path).font(.caption.monospaced()).foregroundColor(.secondary).textSelection(.enabled)
                    CandidateSafetyDetails(candidate: candidate)
                } else {
                    Text(L10n.text("选择一个项目查看发现依据、风险判断、计划动作和恢复方式。"))
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
            InspectorSection(title: L10n.text("项目资料"), icon: "doc.text.magnifyingglass") {
                InspectorFact(label: L10n.text("类别"), value: candidate.category.displayTitle)
                InspectorFact(label: L10n.text("来源"), value: candidate.source.displayTitle)
                InspectorFact(label: L10n.text("大小"), value: ByteCountFormatter.cleanerString(bytes: candidate.bytes))
                InspectorFact(label: L10n.text("活跃状态"), value: candidate.isActive ? L10n.text("正在使用") : L10n.text("扫描时未发现占用"))
                if let date = candidate.lastAccessDate { InspectorFact(label: L10n.text("最近访问"), value: date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.language.locale))) }
            }
            InspectorSection(title: L10n.text("为什么发现"), icon: "magnifyingglass") {
                ForEach(candidate.evidence, id: \.self) { evidence in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(evidence.summary)
                        if let details = evidence.details { Text(details).font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
            InspectorSection(title: L10n.text("风险判断"), icon: candidate.risk == .blocked ? "lock.shield" : "shield.checkered") { Text(candidate.risk.explanation) }
            InspectorSection(title: L10n.text("执行时会发生什么"), icon: "shippingbox") { Text(candidate.plannedActionExplanation) }
            InspectorSection(title: L10n.text("会保留什么"), icon: "checkmark.shield") { Text(candidate.retentionExplanation) }
            InspectorSection(title: L10n.text("如何恢复"), icon: "arrow.uturn.backward.circle") { Text(L10n.text("从恢复记录恢复；若原路径已有文件，会恢复到相邻位置，绝不覆盖。")) }
            InspectorSection(title: L10n.text("执行前复验"), icon: "checkmark.seal") { Text(L10n.text("执行前检查路径、文件身份、适用的活跃状态、规则版本和计划期限；普通清理允许内容更新，重复内容及非缓存 Agent 数据仍需复验。")) }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct CleanupCandidateCard: View {
    @ObservedObject var model: AppModel
    let candidate: CleanupCandidate
    var showsRecommendationBadge = true

    private var manualExplanation: String {
        if let ownership = candidate.evidence.first(where: { $0.code == "cache-reference-ownership" }) {
            return ownership.summary
        }
        if candidate.source == .historicalApplicationResidue {
            return candidate.evidence.first(where: { $0.code == "review-required" })?.summary
                ?? L10n.text("未找到对应应用，但此处可能保留文档或设置；确认不再需要后可单独勾选清理")
        }
        return candidate.evidence.first(where: { $0.code == "manual-only" })?.summary
            ?? L10n.text("必须逐项手动选择；清理后离线内容或共享缓存可能不可用")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CandidateRow(model: model, candidate: candidate, showsRecommendationBadge: showsRecommendationBadge)
            if candidate.requiresExplicitSelection == true {
                Label(manualExplanation, systemImage: "hand.raised")
                    .font(.caption).foregroundColor(.orange)
            }
            Text(candidate.url.path)
                .font(.caption.monospaced()).foregroundColor(.secondary)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if let failure = model.cleanupFailures.first(where: { $0.candidate.id == candidate.id }) {
                Label(failure.reason, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundColor(.orange)
            }
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
            TextField(L10n.text("搜索名称、路径或证据"), text: $model.reviewQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
            Picker(L10n.text("建议"), selection: $model.reviewDispositionFilter) {
                ForEach(ReviewDispositionFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            Toggle(L10n.text("仅显示已选"), isOn: $model.showsSelectedOnly)
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
        case .safe: L10n.text("证据足以表明内容可重建，因此默认加入计划。")
        case .review: L10n.text("内容可能有重建成本或上下文价值，因此系统默认保留；你仍可在自定义模式中加入计划。")
        case .blocked: L10n.text("权限、活跃状态或资产类型不允许自动处理，此项目不会进入计划。")
        }
    }
}

private extension CandidateSource {
    var displayTitle: String {
        switch self {
        case .general: L10n.text("通用扫描")
        case .historicalApplicationResidue: L10n.text("历史卸载残留")
        case .agentWorkspace: L10n.text("Agent 环境")
        case .application: L10n.text("应用卸载")
        case .diskAnalysis: L10n.text("磁盘分析")
        case .projectArtifacts: L10n.text("项目产物")
        }
    }
}

extension CleanupCategory {
    var displayTitle: String {
        switch self {
        case .cache: L10n.text("应用缓存")
        case .log: L10n.text("日志")
        case .temporaryFile: L10n.text("临时文件")
        case .installerArtifact: L10n.text("安装产物")
        case .developerCache: L10n.text("开发工具缓存")
        case .largeFile: L10n.text("重复大文件")
        case .application: L10n.text("应用程序")
        case .applicationSupport: L10n.text("应用支持数据")
        case .agentSkill: "Agent Skill"
        case .agentMCP: "MCP"
        case .agentSession: L10n.text("Agent 会话")
        case .agentSandbox: L10n.text("Agent 沙箱")
        case .agentWorktree: "Git Worktree"
        case .agentModelCache: L10n.text("模型缓存")
        case .agentPackageCache: L10n.text("工具包缓存")
        case .agentUnknown: L10n.text("未识别 Agent 资产")
        case .credential: L10n.text("凭证")
        case .configuration: L10n.text("配置")
        case .userKnowledge: L10n.text("用户知识")
        }
    }
}

extension CleanupDisposition {
    var displayTitle: String {
        switch self {
        case .recommended: L10n.text("低风险")
        case .deepClean: L10n.text("可重建")
        case .retain: L10n.text("建议保留")
        case .protected: L10n.text("始终保护")
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
        risk == .blocked ? L10n.text("不会进入执行计划。") : L10n.text("通过执行前复验后删除，可从恢复记录找回。")
    }

    var retentionExplanation: String {
        source == .agentWorkspace
            ? L10n.text("保留 Skills、MCP 配置、Prompt、凭证、会话和代码；只处理计划中这一条路径。")
            : L10n.text("只处理当前候选路径，不扩展到相邻目录或用户内容。")
    }
}

struct EmptyState: View {
    let title: String, message: String, icon: String
    var body: some View { VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 42)).foregroundColor(.secondary); Text(title).font(.title2.weight(.semibold)); Text(message).foregroundColor(.secondary).multilineTextAlignment(.center) }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40) }
}
