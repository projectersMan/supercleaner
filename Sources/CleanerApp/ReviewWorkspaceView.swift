import CleanerCore
import SwiftUI

struct ReviewWorkspaceView: View {
    @ObservedObject var model: AppModel
    let destination: SidebarDestination
    let emptyTitle: String
    let emptyMessage: String
    let emptyIcon: String
    var showsFilterBar = true

    private var allItems: [CleanupCandidate] { model.candidates(for: destination) }
    private var visibleItems: [CleanupCandidate] { model.visibleCandidates(for: destination) }

    private var focusBinding: Binding<UUID?> {
        Binding(
            get: { model.focusedCandidateID },
            set: { model.focus($0, for: destination) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsFilterBar, !model.showsScanningPlaceholder(for: destination), !allItems.isEmpty {
                ReviewFilterBar(model: model)
            }
            if model.showsScanningPlaceholder(for: destination) {
                EmptyState(title: L10n.text("正在扫描"), message: L10n.text("只读取元数据与必要的引用关系，不执行清理。"), icon: "magnifyingglass")
            } else if allItems.isEmpty {
                EmptyState(title: emptyTitle, message: emptyMessage, icon: emptyIcon)
            } else if visibleItems.isEmpty {
                EmptyState(title: L10n.text("没有符合筛选条件的项目"), message: L10n.text("清除搜索或风险筛选后再查看。已勾选项目不会因此取消。"), icon: "line.3.horizontal.decrease.circle")
            } else if destination == .systemCleanup {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleItems) { candidate in
                            CleanupCandidateCard(model: model, candidate: candidate)
                                .contextMenu {
                                    Button(L10n.text("永久保护此路径")) { model.protect(candidate) }
                                }
                        }
                    }
                    .padding(18)
                }
            } else {
                HSplitView {
                    List(visibleItems, selection: focusBinding) { candidate in
                        CandidateRow(model: model, candidate: candidate)
                            .contextMenu {
                                Button(L10n.text("永久保护此路径")) { model.protect(candidate) }
                            }
                            .tag(candidate.id)
                    }
                    .frame(minWidth: 470)
                    CandidateInspector(
                        candidate: model.inspectedCandidate,
                        isSelected: model.inspectedCandidate.map { model.selectedIDs.contains($0.id) } ?? false,
                        disposition: model.inspectedCandidate.map { model.disposition(for: $0) }
                    )
                }
            }
        }
        .task(id: destination) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            model.reconcileFocus(for: destination)
        }
    }
}
