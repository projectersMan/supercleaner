import CleanerCore
import SwiftUI

struct ScanPermissionPreparationView: View {
    @ObservedObject var model: AppModel

    private var fullDiskAccessGranted: Bool {
        model.permissionSnapshot?.fullDiskAccess.status == .granted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("允许扫描访问"))
                    .font(.title2.bold())
                Text(L10n.text("建议一起准备扫描和卸载所需的两项权限。完全磁盘访问用于扫描；App 管理用于之后卸载其他应用。"))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                permissionRow(
                    icon: "externaldrive.badge.checkmark",
                    title: L10n.text("完全磁盘访问"),
                    status: fullDiskAccessGranted ? L10n.text("已开启") : L10n.text("需要开启"),
                    statusColor: fullDiskAccessGranted ? .green : .orange,
                    detail: fullDiskAccessGranted
                        ? L10n.text("已可扫描受保护位置。")
                        : L10n.text("打开系统设置，开启 SuperCleaner，然后在系统提示中选择“退出并重新打开”。macOS 会自动重新打开本 App，并继续本次扫描。")
                ) {
                    if !fullDiskAccessGranted {
                        Button(L10n.text("打开完全磁盘访问")) { model.preparePermissionsAndScan() }
                    }
                }

                Divider().padding(.leading, 44)

                permissionRow(
                    icon: "app.badge.checkmark",
                    title: L10n.text("App 管理"),
                    status: L10n.text("建议准备"),
                    statusColor: .secondary,
                    detail: L10n.text("现在可以打开“隐私与安全性 > App 管理”：若列表中有 SuperCleaner，请开启；若没有，macOS 会在首次真实卸载时登记并请求权限，届时按系统提示允许。此权限不阻止扫描。")
                ) {
                    Button(L10n.text("查看 App 管理")) { model.openAppManagementSettings() }
                }
            }
            .padding(.horizontal, 16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

            Text(L10n.text("不开启完全磁盘访问也可以扫描；受保护的位置会安全跳过。扫描不会删除任何内容。"))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button(L10n.text("取消")) { model.dismissScanPermissionPreparation() }
                Spacer()
                if !fullDiskAccessGranted {
                    Button(L10n.text("按当前权限开始扫描")) { model.continueScanWithCurrentPermissions() }
                }
                Button(fullDiskAccessGranted ? L10n.text("开始扫描") : L10n.text("打开完全磁盘访问")) {
                    if fullDiskAccessGranted {
                        model.continueScanWithCurrentPermissions()
                    } else {
                        model.preparePermissionsAndScan()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(model.preparingScanPermissions)
        }
        .padding(24)
        .frame(width: 620)
    }

    private func permissionRow<Action: View>(
        icon: String,
        title: String,
        status: String,
        statusColor: Color,
        detail: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).fontWeight(.semibold)
                    Spacer()
                    Text(status).foregroundColor(statusColor)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                action().controlSize(.small)
            }
        }
        .padding(.vertical, 14)
    }
}
