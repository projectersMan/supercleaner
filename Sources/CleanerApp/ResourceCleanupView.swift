import AppKit
import CleanerCore
import Foundation
import SwiftUI

struct ResourceCleanupView: View {
    @ObservedObject var model: AppModel
    let destination: AppDestination

    private var isModels: Bool { destination == .localAIModels }
    private var module: ScanModuleID { isModels ? .localAIModels : .projects }
    private var allItems: [CleanupCandidate] { model.candidates(for: destination) }
    private var visibleItems: [CleanupCandidate] { model.visibleCandidates(for: destination) }
    private var reviewFilter: Binding<ResourceReviewFilter> {
        Binding(get: { model.resourceReviewFilters[destination]! }, set: { model.resourceReviewFilters[destination] = $0 })
    }
    private var sortOrder: LargeFileSortOrder { reviewFilter.wrappedValue.sortOrder }
    private var selectableItems: [CleanupCandidate] { ResourceCleanupListPolicy.selectableCandidates(visibleItems) }
    private var selectionIsDisabled: Bool { model.isDeletionInProgress || model.updateInProgress || model.isCurrentModuleScanning || (isModels && model.modelScanRootsNeedRefresh) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !isModels, let error = model.projectScanRootsError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 8)
            }
            if let message = model.moduleScanProgressMessage(for: module) {
                ModuleProgressView(message: message)
            } else if !model.hasScanResult(for: module) {
                ScanRequiredView(destinationTitle: destination.title) { model.navigateToScan() }
            } else {
                filterBar
                Divider()
                if isModels && model.modelScanRootsNeedRefresh {
                    Label(L10n.text("模型目录已更改或无法读取，请在设置中检查后重新扫描。"), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.orange).padding(8)
                }
                if !isModels, model.projectScanRootsError == nil, model.projectScanRootsNeedRefresh {
                    Label(L10n.text("扫描目录已更改，请重新扫描项目产物。"), systemImage: "arrow.clockwise")
                        .font(.caption).foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                }
                if let status = model.scanProgressByModule[module], !status.limitations.isEmpty {
                    Label(L10n.text("部分目录未完整检查，受影响项目保持保护"), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .help(status.limitations.map { limitation in
                            [limitation.title, limitation.path?.path].compactMap { $0 }.joined(separator: " · ")
                        }.joined(separator: "\n"))
                }
                resourceContent
            }
        }
        .task(id: destination) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            model.reconcileFocus(for: destination)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(destination.title).font(.largeTitle.bold())
                Text(isModels
                    ? L10n.text("按工具查看本地模型与下载缓存，请手动选择要清理的项目。")
                    : L10n.text("按源码工程查看依赖与构建产物，清理后可能需要重新安装或构建。"))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }

    private var filterBar: some View {
        ReviewToolbar(query: reviewFilter.query, prompt: L10n.text("搜索名称或路径")) { metrics in
            selectAll(metrics)
            scopePicker(metrics)
            sortPicker(metrics)
        }
    }

    private func scopePicker(_ metrics: ReviewToolbarMetrics) -> some View {
        let scopes = ResourceCleanupListScope.scopes(for: destination)
        return ScopePicker(labels: scopes.map(\.displayTitle), selection: Binding(
            get: { scopes.firstIndex(of: reviewFilter.wrappedValue.scope)! },
            set: { model.selectResourceReviewScope(scopes[$0], for: destination) }
        ))
        .frame(width: metrics.scopeWidth(count: scopes.count)).fixedSize(horizontal: false, vertical: true)
    }

    private func sortPicker(_ metrics: ReviewToolbarMetrics) -> some View {
        HStack(spacing: metrics.labelSpacing) {
            if !metrics.isCompact { Text(L10n.text("排序")).foregroundColor(.secondary) }
            Picker(L10n.text("排序"), selection: reviewFilter.sortOrder) {
                ForEach(LargeFileSortOrder.allCases, id: \.self) { order in
                    Text(order.displayTitle).tag(order)
                }
            }
            .pickerStyle(.menu).labelsHidden().frame(width: metrics.dropdownWidth)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func selectAll(_ metrics: ReviewToolbarMetrics) -> some View {
        ResourceSelectionCheckbox(state: model.cleanupSelectionState(for: selectableItems, includesManualOnly: true),
            isEnabled: !selectableItems.isEmpty && !selectionIsDisabled,
            title: L10n.text("全选"),
            label: L10n.text("全选当前筛选中可清理的项目")) {
                model.toggleCleanupCategory(selectableItems, includesManualOnly: true)
            }
            .frame(width: metrics.selectAllWidth, height: 18)
            .help(L10n.text("全选当前筛选中可清理的项目"))
    }

    @ViewBuilder private var resourceContent: some View {
        if allItems.isEmpty {
            EmptyState(title: isModels ? L10n.text("未发现本地模型资源") : L10n.text("未发现项目产物"),
                message: isModels ? L10n.text("已检查常见模型工具的默认存储位置。")
                    : L10n.text("可选择源码工程所在目录后重新扫描。"),
                icon: isModels ? "brain" : "shippingbox")
        } else if visibleItems.isEmpty {
            EmptyState(title: L10n.text("没有符合筛选条件的项目"),
                message: L10n.text("调整搜索或范围后再查看。已勾选项目不会因此取消。"),
                icon: "line.3.horizontal.decrease.circle")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(groups) { group in
                        ResourceCleanupGroupRow(model: model, destination: destination, group: group,
                            selectionIsDisabled: selectionIsDisabled)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
    }

    private var groups: [ResourceCleanupGroup] {
        let groups: [ResourceCleanupGroup]
        if isModels {
            let records = model.systemReport?.localAIModelInventory?.models ?? []
            groups = LocalAIModelProvider.allCases.compactMap { provider in
                let providerIDs = Set(records.filter { $0.provider == provider }.map(\.id))
                let candidates = visibleItems.filter { providerIDs.contains($0.id) }
                guard !candidates.isEmpty else { return nil }
                let paths = Set(candidates.compactMap { candidate in
                    candidate.evidence.first { $0.code == "local-ai-model-provider" }?.details
                }).sorted()
                return ResourceCleanupGroup(id: provider.rawValue, title: provider.displayName,
                    detail: paths.joined(separator: " · "),
                    notice: provider == .ollama
                        ? L10n.text("按模型选择清理；其他模型仍引用的共享文件会保留。")
                        : L10n.text("清理后可能需要重新下载。"),
                    icon: "brain", candidates: candidates)
            }
        } else {
            let grouped = Dictionary(grouping: visibleItems, by: projectPath)
            groups = grouped.keys.sorted().map { path in
                ResourceCleanupGroup(id: path,
                    title: path.isEmpty ? L10n.text("项目来源无法验证") : URL(fileURLWithPath: path).lastPathComponent,
                    detail: path, notice: nil, icon: "folder.fill", candidates: grouped[path]!)
            }
        }
        return groups.sorted { lhs, rhs in
            if sortOrder == .selection {
                let leftSelected = lhs.candidates.contains { model.selectedIDs.contains($0.id) }
                let rightSelected = rhs.candidates.contains { model.selectedIDs.contains($0.id) }
                if leftSelected != rightSelected { return leftSelected }
            }
            if sortOrder == .directory && lhs.detail != rhs.detail {
                return lhs.detail.localizedStandardCompare(rhs.detail) == .orderedAscending
            }
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    private func projectPath(_ candidate: CleanupCandidate) -> String {
        candidate.evidence.first { $0.code == "project-root" }?.details ?? ""
    }
}

private struct ResourceCleanupGroup: Identifiable {
    let id: String
    let title: String
    let detail: String
    let notice: String?
    let icon: String
    let candidates: [CleanupCandidate]
    var bytes: UInt64 {
        CleanupSelection.executionCandidates(from: candidates).reduce(0) { total, candidate in
            let (sum, overflow) = total.addingReportingOverflow(candidate.bytes)
            return overflow ? .max : sum
        }
    }
}

private struct ResourceCleanupGroupRow: View {
    @ObservedObject var model: AppModel
    let destination: AppDestination
    let group: ResourceCleanupGroup
    let selectionIsDisabled: Bool
    @State private var isExpanded = true

    private var selectableItems: [CleanupCandidate] { ResourceCleanupListPolicy.selectableCandidates(group.candidates) }
    private var selectionState: SelectionTriState {
        model.cleanupSelectionState(for: selectableItems, includesManualOnly: true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ResourceSelectionCheckbox(state: selectionState,
                    isEnabled: !selectableItems.isEmpty && !selectionIsDisabled, title: "", label: group.title) {
                        model.toggleCleanupCategory(selectableItems, includesManualOnly: true)
                    }
                    .frame(width: 18, height: 18)
                    .help(L10n.text("全选当前筛选中可清理的项目"))
                Button { isExpanded.toggle() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold)).frame(width: 16)
                        Image(systemName: group.icon).foregroundColor(.accentColor).frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.title).fontWeight(.semibold).lineLimit(1)
                            if !group.detail.isEmpty {
                                Text(group.detail).font(.caption.monospaced()).foregroundColor(.secondary)
                                    .lineLimit(1).truncationMode(.middle).help(group.detail)
                            }
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(ByteCountFormatter.cleanerString(bytes: group.bytes)).fontWeight(.semibold)
                            Text(L10n.text("{0} 项", String(group.candidates.count))).font(.caption).foregroundColor(.secondary)
                        }
                        .monospacedDigit().fixedSize()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? L10n.text("折叠 {0}", group.title) : L10n.text("展开 {0}", group.title))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
            .contextMenu {
                if destination == .projects, group.detail.hasPrefix("/") {
                    let projectURL = URL(fileURLWithPath: group.detail)
                    Button(L10n.text("在 Finder 中打开")) {
                        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
                    }
                    Button(L10n.text("永久保护此路径")) { model.protect(projectURL) }
                        .disabled(selectionIsDisabled)
                }
            }
            if let notice = group.notice {
                Text(notice).font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 44).padding(.trailing, 14).padding(.bottom, 10)
            }
            if isExpanded {
                Divider().padding(.leading, 44)
                ForEach(group.candidates) { candidate in
                    ResourceCleanupCandidateRow(model: model, destination: destination, candidate: candidate,
                        selectionIsDisabled: selectionIsDisabled)
                }
            }
        }
        .background(selectionState != .none ? Color.accentColor.opacity(0.06) : Color.secondary.opacity(0.03),
            in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.12)))
    }
}

private struct ResourceCleanupCandidateRow: View {
    @ObservedObject var model: AppModel
    let destination: AppDestination
    let candidate: CleanupCandidate
    let selectionIsDisabled: Bool

    private var isSelectable: Bool { ResourceCleanupListPolicy.isSelectable(candidate) }
    private var restrictionSummary: String? {
        guard !isSelectable else { return nil }
        if let protection = candidate.evidence.last(where: { $0.code == "protected-by-policy" || $0.code == "protection-unavailable" }) {
            return protection.summary
        }
        if let incomplete = candidate.evidence.first(where: { $0.code.hasPrefix("scan-incomplete-") }) { return incomplete.summary }
        return candidate.evidence.first {
            ["nested-git", "deployment-key", "inspection-failed", "inspection-budget", "local-ai-model-budget", "local-ai-model-unverified"].contains($0.code)
        }?.summary ?? candidate.evidence.first { $0.code == "git-status" }?.summary ?? L10n.text("始终保护")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { model.selectedIDs.contains(candidate.id) },
                    set: { _ in
                        model.focus(candidate.id, for: destination)
                        model.toggle(candidate)
                    }
                )) { EmptyView() }
                .toggleStyle(.checkbox).labelsHidden().disabled(!isSelectable || selectionIsDisabled)
                .accessibilityLabel(SelectionLabelPolicy.cleanupToggle(name: candidate.displayName,
                    isSelected: model.selectedIDs.contains(candidate.id), isBlocked: !isSelectable))
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.displayName).font(.callout.weight(.medium)).lineLimit(1).help(candidate.displayName)
                    Text(candidate.url.path).font(.caption.monospaced()).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(candidate.url.path)
                    if let restrictionSummary {
                        Label(restrictionSummary, systemImage: "lock.fill")
                            .font(.caption).foregroundColor(.secondary).lineLimit(2).help(restrictionSummary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(candidate.hasIncompleteScan ? L10n.text("容量未确认") : ByteCountFormatter.cleanerString(bytes: candidate.bytes))
                    .font(.callout).monospacedDigit().foregroundColor(.secondary).fixedSize()
            }
            if let failure = model.cleanupFailures.first(where: { $0.candidate.id == candidate.id }) {
                Label(failure.reason, systemImage: "exclamationmark.circle").font(.caption).foregroundColor(.orange)
            }
        }
        .padding(.leading, 44).padding(.trailing, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(model.selectedIDs.contains(candidate.id) ? Color.accentColor.opacity(0.06) : Color.clear)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.secondary.opacity(0.10)), alignment: .bottom)
        .contextMenu {
            Button(L10n.text("在 Finder 中打开"), action: revealInFinder)
            Button(L10n.text("永久保护此路径")) { model.protect(candidate) }
                .disabled(selectionIsDisabled)
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
    }
}

struct ResourceSelectionCheckbox: NSViewRepresentable {
    let state: SelectionTriState
    let isEnabled: Bool
    let title: String
    let label: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.toggleSelection(_:)))
        button.allowsMixedState = true
        button.controlSize = .small
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.state = state == .all ? .on : state == .partial ? .mixed : .off
        button.isEnabled = isEnabled && context.environment.isEnabled
        button.setAccessibilityLabel(label)
    }

    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func toggleSelection(_ sender: NSButton) { action() }
    }
}

private extension ResourceCleanupListScope {
    var displayTitle: String {
        switch self {
        case .all: L10n.text("全部")
        case .cleanable: L10n.text("可清理")
        case .protected: L10n.text("受保护")
        case .selected: L10n.text("已选择")
        }
    }
}
