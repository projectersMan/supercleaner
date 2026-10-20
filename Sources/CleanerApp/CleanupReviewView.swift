import CleanerCore
import SwiftUI

struct CleanupReviewView: View {
    @ObservedObject var model: AppModel
    let destination: SidebarDestination
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.largeTitle.bold())
                    Text(destination == .systemCleanup
                         ? L10n.text("按建议分组展示完整可清理范围；可直接逐项勾选或保留。")
                         : L10n.text("查看路径与判断依据；勾选表示加入计划，未勾选表示保留。"))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(24)
            Divider()
            if !model.hasScanResult(for: .general) {
                ScanRequiredView(destinationTitle: title) { model.navigateToScan() }
            } else if destination == .systemCleanup {
                GuidedCleanupView(model: model)
            } else {
                ReviewWorkspaceView(
                    model: model,
                    destination: destination,
                    emptyTitle: L10n.text("还没有扫描结果"),
                    emptyMessage: L10n.text("返回概览开始完整扫描。"),
                    emptyIcon: "shield.checkered"
                )
            }
        }
    }
}
