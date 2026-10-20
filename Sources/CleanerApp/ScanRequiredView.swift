import CleanerCore
import SwiftUI

struct ScanRequiredView: View {
    let destinationTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "internaldrive.badge.magnifyingglass")
                .font(.system(size: 44)).foregroundColor(.secondary)
            Text(L10n.text("尚未扫描")).font(.title2.bold())
            Text(L10n.text("{0}的数据来自清理中心的完整系统扫描。先扫描一次，再回来查看同一份报告。", String(describing: destinationTitle)))
                .foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 430)
            Button(L10n.text("前往清理中心开始扫描"), action: action)
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}
