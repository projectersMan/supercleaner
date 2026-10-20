import CleanerCore
import SwiftUI

struct DeletionResultSheet: View {
    @ObservedObject var model: AppModel
    let receipt: OperationReceipt

    private var deleted: Int { receipt.results.filter { $0.disposition == .quarantined }.count }
    private var skipped: Int { receipt.results.filter { $0.disposition == .skipped }.count }
    private var failed: Int { receipt.results.filter { $0.disposition == .failed }.count }
    private var retryableFailures: [DefaultCleanupFailure] {
        let resultIDs = Set(receipt.results.map(\.candidateID))
        return model.cleanupFailures.filter {
            resultIDs.contains($0.candidate.id) && $0.isRetryable
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("删除结果"), systemImage: receipt.overallStatus == .completed ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.title.bold())
            Text(L10n.text("已删除 {0} 项 · 跳过 {1} 项 · 失败 {2} 项", String(describing: deleted), String(describing: skipped), String(describing: failed)))
                .font(.headline)
            Text(L10n.text("已删除项目可在保留期内从恢复记录找回；保留期间仍占用磁盘空间。"))
                .foregroundColor(.secondary)
            if let warning = model.deletionResultWarning {
                Text(warning).foregroundColor(.orange)
            }
            Divider()
            List(receipt.results) { result in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.originalURL.lastPathComponent).fontWeight(.medium)
                        Text(result.originalURL.path).font(.caption).foregroundColor(.secondary)
                        if let message = result.message {
                            Text(L10n.text("原因：{0}", String(describing: message))).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(result.disposition == .quarantined ? L10n.text("已删除") : result.disposition == .skipped ? L10n.text("已跳过") : L10n.text("失败"))
                        .foregroundColor(result.disposition == .quarantined ? .green : .orange)
                }
                .padding(.vertical, 5)
            }
            HStack {
                Button(L10n.text("查看恢复记录")) {
                    model.deletionResult = nil
                    model.selection = .recovery
                }
                if !retryableFailures.isEmpty {
                    Button(L10n.text("安全重试 {0} 项", String(describing: retryableFailures.count))) {
                        let failures = retryableFailures
                        model.deletionResult = nil
                        model.retryCleanupFailures(failures)
                    }
                }
                Spacer()
                Button(L10n.text("完成")) { model.deletionResult = nil }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 460)
    }
}
