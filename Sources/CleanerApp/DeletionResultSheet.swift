import CleanerCore
import SwiftUI

struct DeletionResultSheet: View {
    @ObservedObject var model: AppModel
    let receipt: OperationReceipt

    private var retryableFailures: [DefaultCleanupFailure] {
        let resultIDs = Set(receipt.results.map(\.candidateID))
        return model.cleanupFailures.filter {
            resultIDs.contains($0.candidate.id) && $0.isRetryable
        }
    }

    var body: some View {
        let presentation = DeletionResultPresentation(results: receipt.results)
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("删除结果"), systemImage: receipt.overallStatus == .completed && presentation.failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.title.bold())
            Text(L10n.text("已删除 {0} 项 · 跳过 {1} 项 · 失败 {2} 项", String(describing: presentation.deletedCount), String(describing: presentation.skippedCount), String(describing: presentation.failedCount)))
                .font(.headline)
            ForEach(presentation.recoveryMessages, id: \.self) { message in
                Text(message).foregroundColor(.secondary)
            }
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
                            Text(message).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text(DeletionResultPresentation.statusTitle(for: result))
                        .foregroundColor(DeletionResultPresentation.outcome(for: result) == .deleted ? .green : .orange)
                }
                .padding(.vertical, 5)
            }
            HStack {
                Button(L10n.text("查看恢复记录")) {
                    model.dismissDeletionSheet()
                    model.selection = .recovery
                }
                if !retryableFailures.isEmpty {
                    Button(L10n.text("安全重试 {0} 项", String(describing: retryableFailures.count))) {
                        let failures = retryableFailures
                        model.dismissDeletionSheet()
                        model.retryCleanupFailures(failures)
                    }
                }
                Spacer()
                Button(L10n.text("完成")) { model.dismissDeletionSheet() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 460)
    }
}
