import CleanerCore
import SwiftUI

struct GuidedCleanupView: View {
    @ObservedObject var model: AppModel
    @State private var cleanupExpanded = true
    @State private var retainedExpanded = true

    private var centerCandidates: [CleanupCandidate] { model.candidates(for: .systemCleanup) }
    private var breakdown: CleanupRecommendationBreakdown { model.recommendationBreakdown(for: .systemCleanup) }
    private var cleanupCandidates: [CleanupCandidate] { breakdown.recommended + breakdown.deepClean }
    private var retainedCandidates: [CleanupCandidate] { breakdown.retained + breakdown.protected }

    var body: some View {
        VStack(spacing: 0) {
            if model.showsScanningPlaceholder(for: .systemCleanup) {
                EmptyState(title: "正在更新扫描结果", message: "当前报告仍被保留，新报告完成后会重新生成方案。", icon: "magnifyingglass")
            } else if centerCandidates.isEmpty {
                EmptyState(title: "没有建议清理的内容", message: "本次扫描没有发现符合安全规则的系统清理项。", icon: "checkmark.shield")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        DispositionCandidatesDisclosure(
                            model: model,
                            title: "建议清理",
                            subtitle: cleanupCandidates.isEmpty ? "本次扫描没有符合安全规则的可清理项目" : "低风险项目和深度清理候选",
                            icon: "checkmark.shield",
                            candidates: cleanupCandidates,
                            isExpanded: $cleanupExpanded,
                            onSelectCandidate: focusCandidate
                        )
                        DispositionCandidatesDisclosure(
                            model: model,
                            title: "建议保留",
                            subtitle: retainedCandidates.isEmpty
                                ? "本次扫描没有需要保留复核的项目"
                                : "可在自定义模式中逐项复核；受保护项目仍不能加入删除计划",
                            icon: "archivebox",
                            candidates: retainedCandidates,
                            isExpanded: $retainedExpanded,
                            onSelectCandidate: focusCandidate
                        )
                    }
                    .padding(.horizontal, 24).padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func focusCandidate(_ candidate: CleanupCandidate) {
        model.focus(candidate.id, for: .systemCleanup)
    }
}

private struct DispositionCandidatesDisclosure: View {
    @ObservedObject var model: AppModel
    let title: String
    let subtitle: String
    let icon: String
    let candidates: [CleanupCandidate]
    @Binding var isExpanded: Bool
    let onSelectCandidate: (CleanupCandidate) -> Void

    private var totalBytes: UInt64 { candidates.reduce(0) { $0 + $1.bytes } }
    private var selectionState: SelectionTriState { model.cleanupSelectionState(for: candidates) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { isExpanded.toggle() } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(.caption.weight(.semibold)).foregroundColor(.secondary).frame(width: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "折叠\(title)" : "展开\(title)")
                Image(systemName: icon).foregroundColor(.accentColor).frame(width: 22)
                Button { model.toggleCleanupCategory(candidates) } label: {
                    Image(systemName: selectionState.icon)
                        .foregroundColor(selectionState == .none ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(candidates.allSatisfy { !$0.risk.isSelectable })
                .accessibilityLabel("\(title)，\(selectionState.accessibilityTitle)")
                Button { isExpanded.toggle() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(title) \(candidates.count) 项").fontWeight(.medium)
                        Text(subtitle).font(.caption).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(ByteCountFormatter.cleanerString(bytes: totalBytes)).foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            if isExpanded {
                LazyVStack(spacing: 12) {
                    ForEach(candidates.sorted { $0.bytes > $1.bytes }) { candidate in
                        CleanupCandidateCard(model: model, candidate: candidate)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectCandidate(candidate) }
                    }
                }
                .padding(.top, 10)
                    .padding(.leading, 30)
            }
        }
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.secondary.opacity(0.12)), alignment: .bottom)
    }
}

private extension SelectionTriState {
    var icon: String {
        switch self { case .none: "square"; case .partial: "minus.square.fill"; case .all: "checkmark.square.fill" }
    }
    var accessibilityTitle: String {
        switch self { case .none: "未选择"; case .partial: "部分选择"; case .all: "全部选择" }
    }
}
