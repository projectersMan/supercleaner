import CleanerCore
import SwiftUI

/// One sheet owns the whole operation so progress switches directly to its
/// receipt (or an error) without competing sheet presentations.
struct DeletionOperationSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.isDeletionInProgress {
                progress
            } else if let receipt = model.deletionResult {
                DeletionResultSheet(model: model, receipt: receipt)
            } else if model.deletionResultWarning != nil {
                failure
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .interactiveDismissDisabled(model.isDeletionInProgress)
    }

    private var progress: some View {
        let total = max(1, model.executionProgress.total)
        let completed = min(total, max(0, model.executionProgress.completed))
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(progressTitle)
                    .font(.title2.bold())
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(model.executionProgressDescription)
                    .font(.headline).monospacedDigit()
                if model.executionProgress.phase == .movingToTrash, model.executionProgress.currentURL != nil {
                    // macOS reports completion per item, not bytes copied within
                    // a single system Trash operation. Do not invent a fraction.
                    ProgressView().progressViewStyle(.linear)
                } else {
                    ProgressView(value: Double(completed), total: Double(total))
                        .progressViewStyle(ImmediateLinearProgressStyle())
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                if model.isStoppingDeletion {
                    Text(L10n.text("正在停止…")).fontWeight(.medium)
                    Text(L10n.text("当前项目处理结束后停止，已经完成的操作不会自动撤销。"))
                        .foregroundColor(.secondary)
                } else if model.executionProgress.phase == .savingResults {
                    Text(L10n.text("正在保存清理和恢复记录…")).foregroundColor(.secondary)
                } else if model.executionProgress.total > 0 && completed == total {
                    Text(L10n.text("正在保存清理和恢复记录…")).foregroundColor(.secondary)
                } else if let url = model.executionProgress.currentURL {
                    Text(url.lastPathComponent).fontWeight(.medium).lineLimit(2)
                    Text(url.path).font(.caption.monospaced()).foregroundColor(.secondary)
                        .textSelection(.enabled).lineLimit(3)
                    if let started = model.executionItemStartedAt {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text(L10n.text("当前文件已用 {0} 秒", String(max(0, Int(context.date.timeIntervalSince(started))))))
                                .font(.caption).foregroundColor(.secondary).monospacedDigit()
                        }
                    }
                } else {
                    Text(L10n.text("正在准备删除…")).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            Text(L10n.text("处理完成后会显示实际结果和各项目的恢复方式。"))
                .font(.callout).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(model.isStoppingDeletion ? L10n.text("正在停止…") : L10n.text("停止后续项目")) {
                    model.cancelExecution()
                }
                .disabled(model.isStoppingDeletion || model.executionProgress.phase != .processing)
            }
        }
        .padding(28)
        .frame(width: 680)
    }

    private var progressTitle: String {
        switch model.executionProgress.phase {
        case .movingToTrash: L10n.text("正在移入系统废纸篓")
        case .savingResults: L10n.text("正在保存清理和恢复记录…")
        case .processing: model.activeCleanupModules == [.applications]
            ? L10n.text("正在删除应用内容") : L10n.text("正在检查并删除所选项目")
        }
    }

    private var failure: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("删除未完成"), systemImage: "exclamationmark.circle")
                .font(.title2.bold()).foregroundColor(.orange)
            Text(model.deletionResultWarning ?? L10n.text("删除未完成"))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.text("查看恢复记录")) {
                    model.dismissDeletionSheet()
                    model.selection = .recovery
                }
                Spacer()
                Button(L10n.text("完成")) { model.dismissDeletionSheet() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 680)
    }
}
