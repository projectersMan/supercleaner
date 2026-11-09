import CleanerCore
import Foundation
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var hoveredModule: ScanModuleID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                scanCoverage
                preScanTrust
            }
            .padding(.horizontal, 34).padding(.vertical, 28)
        }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 26) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 54)).foregroundStyle(.tint).frame(width: 72)
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.text("先完整扫描，再决定清理什么")).font(.system(size: 34, weight: .semibold))
                Text(L10n.text("扫描所有受支持且可安全访问的位置，统一生成系统清理、应用、重复大文件和 Agent 环境报告。扫描过程零写入。"))
                    .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    Button(action: model.startFullScan) {
                        Label(L10n.text("开始完整扫描"), systemImage: "magnifyingglass")
                            .font(.headline).padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isScanRunning || model.bootstrapInProgress || model.oneClickCleanupIsRunning)
                    .accessibilityHint(L10n.text("只读扫描系统清理、应用、重复大文件和 Agent 环境"))
                    fullScanElapsed
                }
                .padding(.top, 8)
            }
            Spacer()
        }
        .padding(.vertical, 14)
    }

    private var fullScanElapsed: some View {
        Group {
            if let startedAt = model.fullScanStartedAt {
                if let stoppedAt = model.fullScanStoppedAt {
                    elapsedText(from: startedAt, to: stoppedAt)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        elapsedText(from: startedAt, to: context.date)
                    }
                }
            } else {
                Text(L10n.text("扫描用时：{0}", "00:00:00")).hidden()
            }
        }
        .font(.subheadline).foregroundColor(.secondary).monospacedDigit()
        .lineLimit(1).frame(width: 180, alignment: .leading)
    }

    private func elapsedText(from startedAt: Date, to current: Date) -> Text {
        let seconds = max(0, Int(current.timeIntervalSince(startedAt)))
        let duration = String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        return Text(L10n.text("扫描用时：{0}", duration))
    }

    private var scanCoverage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text("一次扫描包含")).font(.title2.bold())
            VStack(spacing: 0) {
                ForEach(ScanModuleID.allCases, id: \.self) { module in
                    moduleScopeRow(module)
                    if module != .agentEnvironment { Divider() }
                }
            }
            .padding(.horizontal, 8)
            Label(L10n.text("扫描受支持的位置，不声称遍历启动磁盘的每一个字节"), systemImage: "info.circle")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func moduleScopeRow(_ module: ScanModuleID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.openScanResult(module)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: module.icon).font(.title2).foregroundColor(module.color).frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(module.resultDestinationTitle).fontWeight(.semibold)
                        Text(module.scopeDetail).font(.caption).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    HStack {
                        if let status = model.scanProgressByModule[module] {
                            ScanModuleStateView(state: status.state)
                        }
                    }
                    .frame(width: 150, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .frame(minHeight: 66)
                .background(hoveredModule == module ? Color.accentColor.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveredModule = $0 ? module : nil }
            .accessibilityHint(L10n.text("打开{0}扫描结果", module.resultDestinationTitle))
            let failures = model.cleanupFailures(for: module)
            if !failures.isEmpty { moduleFailureList(failures, module: module) }
        }
    }


    private var preScanTrust: some View {
        HStack(spacing: 14) {
            TrustItem(icon: "eye", title: L10n.text("扫描可解释"), detail: L10n.text("每项都显示路径和发现依据"))
            TrustItem(icon: "play.circle", title: L10n.text("删除前检查"), detail: L10n.text("自动复验，跳过变化或占用项"))
            TrustItem(icon: "arrow.uturn.backward.circle", title: L10n.text("默认可恢复"), detail: L10n.text("删除后可恢复，恢复不覆盖原文件"))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func moduleFailureList(_ failures: [DefaultCleanupFailure], module: ScanModuleID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(failures) { failure in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: failure.isRetryable ? "arrow.clockwise.circle" : "exclamationmark.triangle")
                        .foregroundColor(failure.isRetryable ? .orange : .secondary)
                    Text(failure.candidate.displayName).fontWeight(.medium).lineLimit(1)
                    Text(failure.reason).foregroundColor(.secondary).lineLimit(2)
                    Spacer()
                    Text(
                        failure.isRetryable
                            ? model.hasScanResult(for: module) ? L10n.text("可安全重试") : L10n.text("扫描完成后可重试")
                            : L10n.text("需重新扫描")
                    )
                    .foregroundColor(failure.isRetryable ? .orange : .secondary)
                }
                .font(.caption)
            }
            let retryable = failures.filter(\.isRetryable)
            if !retryable.isEmpty {
                Button(
                    L10n.text("安全重试 {0} 项", String(describing: retryable.count))
                ) {
                    model.retryCleanupFailures(retryable)
                }
                .controlSize(.small)
                .disabled(!model.canRetryCleanupFailures(retryable))
            }
        }
        .padding(.leading, 44)
        .padding(.trailing, 8)
    }

}

private struct ScanModuleStateView: View {
    let state: ScanModuleState
    var body: some View {
        Group {
            if state == .scanning { HStack(spacing: 7) { ProgressView().controlSize(.small); Text(L10n.text("扫描中")) } }
            else { Label(state.title, systemImage: state.icon) }
        }
        .font(.caption.weight(.semibold)).foregroundColor(state.color)
    }
}

private struct TrustItem: View {
    let icon: String, title: String, detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension ScanModuleID {
    var scopeDetail: String {
        switch self {
        case .general: L10n.text("缓存、日志、临时文件、安装包、开发缓存")
        case .applications: L10n.text("以 App 为单位，展开应用本体与精确关联项")
        case .largeFiles: L10n.text("识别安装包，核验相同副本和已完整解压的 ZIP")
        case .agentEnvironment: L10n.text("按真实目录和 Skill 标记动态组织，再逐条决定删或不删")
        }
    }

    var title: String {
        switch self { case .general: L10n.text("系统清理"); case .applications: L10n.text("应用"); case .largeFiles: L10n.text("重复大文件"); case .agentEnvironment: L10n.text("Agent 环境") }
    }
    var icon: String {
        switch self { case .general: "trash"; case .applications: "app.dashed"; case .largeFiles: "doc.text.magnifyingglass"; case .agentEnvironment: "terminal" }
    }
    var color: Color {
        switch self { case .general: .green; case .applications: .blue; case .largeFiles: .orange; case .agentEnvironment: .purple }
    }
    var resultDestinationTitle: String {
        switch self { case .general: L10n.text("系统清理"); case .applications: L10n.text("应用卸载"); case .largeFiles: L10n.text("重复大文件"); case .agentEnvironment: L10n.text("Agent 环境") }
    }
}

private extension ScanModuleState {
    var title: String {
        switch self {
        case .waiting: L10n.text("等待")
        case .scanning: L10n.text("扫描中")
        case .completed, .limited: L10n.text("扫描完成")
        case .failed: L10n.text("失败")
        case .cancelled: L10n.text("已取消")
        }
    }
    var icon: String {
        switch self {
        case .waiting: "clock"
        case .scanning: "magnifyingglass"
        case .completed, .limited: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "stop.circle"
        }
    }
    var color: Color {
        switch self {
        case .waiting: .secondary
        case .scanning: .accentColor
        case .completed, .limited: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}
