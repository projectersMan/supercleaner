import CleanerCore
import SwiftUI

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
    }
}

struct DimensionActionBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Divider()
        if model.selection == .applications {
            applicationSelectionBar
                .background(.bar)
        } else {
            candidateSelectionBar
                .background(.bar)
        }
    }

    private var applicationSelectionBar: some View {
        let summary = model.uninstallBatchSummary
        return SelectionActionBar(
            hasSelection: summary.itemCount > 0,
            title: model.isCurrentModuleScanning
                ? L10n.text("正在扫描应用卸载")
                : model.phase == .executing
                    ? L10n.text("正在删除应用内容")
                    : summary.itemCount == 0
                        ? L10n.text("尚未选择卸载内容")
                        : L10n.text("已选 {0} 个应用 · {1} 项", String(describing: summary.applicationCount), String(describing: summary.itemCount)),
            detail: model.isCurrentModuleScanning
                ? L10n.text("正在扫描，报告就绪后可确认删除。")
                : model.phase == .executing
                    ? model.executionProgressDescription
                    : summary.itemCount == 0
                        ? L10n.text("当前没有已选项目。可手动勾选应用，或展开后逐项选择；扫描不会默认选中任何卸载项。")
                        : L10n.text("约 {0}；删除后可在恢复记录中找回。", String(describing: ByteCountFormatter.cleanerString(bytes: summary.bytes)))
        ) {
            if model.canResumeCurrentModuleScan {
                Button(L10n.text("继续扫描")) { model.resumeCurrentModuleScan() }
            }
            if model.isCurrentModuleScanning {
                ProgressView().controlSize(.small)
                Button(L10n.text("取消扫描")) { model.cancelCurrentModuleScan() }
            } else if model.phase == .executing {
                ProgressView().controlSize(.small)
                Button(L10n.text("停止后续项目")) { model.cancelExecution() }
                    .disabled(model.isStoppingDeletion)
            } else if summary.itemCount > 0 {
                Button(L10n.text("清空选择")) { model.clearUninstallSelection() }
            }
            Button { model.executeUninstallBatch() } label: {
                Label(L10n.text("确认删除"), systemImage: "trash.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canExecuteUninstallBatch)
        }
    }

    private var candidateSelectionBar: some View {
        let selected = model.executionSelectionCandidates
        let count = model.selection == .localAIModels ? model.selectedCandidates.count : selected.count
        let bytes = selected.reduce(UInt64(0)) { $0 + $1.bytes }
        return SelectionActionBar(
            hasSelection: !selected.isEmpty,
            title: selected.isEmpty ? L10n.text("尚未选择清理内容")
                : L10n.text(model.selection == .agentEnvironment ? "已选 {0} 个清理单元" : "已选 {0} 项", String(describing: count)),
            detail: detail(count: count, bytes: bytes)
        ) {
            if model.canResumeCurrentModuleScan {
                Button(L10n.text("继续扫描")) { model.resumeCurrentModuleScan() }
            }
            if model.isCurrentModuleScanning {
                ProgressView().controlSize(.small)
                Button(L10n.text("取消扫描")) { model.cancelCurrentModuleScan() }
                deleteButton.disabled(true)
            } else if model.phase == .executing {
                ProgressView().controlSize(.small)
                Button(L10n.text("停止后续项目")) { model.cancelExecution() }
                    .disabled(model.isStoppingDeletion)
                deleteButton.disabled(true)
            } else {
                if !selected.isEmpty {
                    Button(L10n.text("清空选择")) { model.clearCurrentSelection() }
                }
                deleteButton.disabled(!model.canExecuteSelection)
            }
        }
    }

    private var deleteButton: some View {
        Button {
            model.requestExecution()
        } label: {
            Label(L10n.text("确认删除"), systemImage: "trash.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func detail(count: Int, bytes: UInt64) -> String {
        if model.isCurrentModuleScanning { return L10n.text("正在扫描，报告就绪后可确认删除。") }
        if model.phase == .executing {
            return model.executionProgressDescription
        }
        if case .failed = model.phase, let message = model.statusMessage { return message }
        guard count > 0 else { return L10n.text("勾选需要清理的项目，删除后可在恢复记录中找回。") }
        let hidden = model.hiddenSelectedCount
        let hiddenDetail = hidden > 0 ? L10n.text("其中 {0} 项被筛选隐藏；", String(describing: hidden)) : ""
        return L10n.text("约 {0}；{1}删除后可在恢复记录中找回。", String(describing: ByteCountFormatter.cleanerString(bytes: bytes)), String(describing: hiddenDetail))
    }
}

struct OneClickCleanupActionBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let defaults = model.defaultCleanupSelection
        let candidates = defaults?.candidates ?? []
        let candidateCount = candidates.count
        let bytes = candidates.reduce(UInt64(0)) { $0 + $1.bytes }

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
                Label(model.oneClickCleanupIsRunning ? L10n.text("正在清理默认项…") : L10n.text("清理全部默认项"), systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canRunOneClickCleanup)
            .accessibilityHint(L10n.text("清理各维度仍默认勾选的内容，不包含手动选择的项目"))
        }
        .background(SidebarSurface())
    }

    private func title(candidateCount: Int) -> String {
        if model.oneClickCleanupIsRunning { return L10n.text("正在清理默认项…") }
        if candidateCount > 0 {
            return L10n.text("默认清理已就绪 · {0} 项", String(candidateCount))
        }
        guard ScanModuleID.allCases.contains(where: { model.hasScanResult(for: $0) }) else {
            return L10n.text("等待默认项扫描完成")
        }
        return L10n.text("当前无需默认清理")
    }

    private func detail(candidateCount: Int, bytes: UInt64) -> String {
        if model.oneClickCleanupIsRunning {
            return model.executionProgressDescription
        }
        if case .failed = model.phase, let message = model.statusMessage { return message }
        guard candidateCount > 0 else {
            return L10n.text("默认项就绪后可清理；手动选择的内容请到对应页面确认。")
        }
        return L10n.text("约 {0}；清理所有已默认勾选的项目，可从恢复记录找回。",
            ByteCountFormatter.cleanerString(bytes: bytes))
    }
}
