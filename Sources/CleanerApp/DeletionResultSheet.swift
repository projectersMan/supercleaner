import CleanerCore
import SwiftUI

struct DeletionResultSheet: View {
    @ObservedObject var model: AppModel
    let receipt: OperationReceipt

    var body: some View {
        let presentation = DeletionResultPresentation(results: receipt.results)
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.text("删除结果"), systemImage: "checkmark.circle.fill")
                .font(.title.bold())
            Text(L10n.text("已删除 {0} 项", String(describing: presentation.deletedCount)))
                .font(.headline)
            ForEach(presentation.recoveryMessages, id: \.self) { message in
                Text(message).foregroundColor(.secondary)
            }
            Divider()
            List(receipt.results.filter { DeletionResultPresentation.outcome(for: $0) == .deleted }) { result in
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
                Spacer()
                Button(L10n.text("完成")) { model.dismissDeletionSheet() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 460)
    }
}
