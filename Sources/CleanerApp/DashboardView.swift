import CleanerCore
import Foundation
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @EnvironmentObject private var trashReminder: TrashReminderController
    @State private var hoveredModule: ScanModuleID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            hero
            scanCoverage
                .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 32)).foregroundStyle(.tint).frame(width: 40)
                Text(L10n.text("先完整扫描，再决定清理什么"))
                    .font(.system(size: 24, weight: .semibold))
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 10) {
                preScanTrust
                HStack(spacing: 12) {
                    scanControls
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    sessionCleanupMetric
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
                .frame(height: 112)
            }
            .padding(.leading, 52)
            .padding(.trailing, 24)
        }
    }

    private var scanControls: some View {
        HStack(spacing: 16) {
            Button(action: model.startFullScan) {
                Label(L10n.text("开始完整扫描"), systemImage: "magnifyingglass")
                    .font(.headline).padding(.horizontal, 21).frame(height: 56)
            }
            .buttonStyle(ScanButtonStyle())
            .disabled(model.isScanRunning || model.bootstrapInProgress || model.oneClickCleanupIsRunning)
            .accessibilityHint(L10n.text("只读扫描全部六个清理维度"))
            fullScanElapsed
        }
    }

    private var sessionCleanupMetric: some View {
        VStack(spacing: 3) {
            Text(L10n.text("本次累计清理")).font(.caption).foregroundColor(.secondary)
            Text(ByteCountFormatter.cleanerString(bytes: model.sessionCleanupSummary.bytes))
                .font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(.tint)
            Text(L10n.text("全部模块 · {0} 项", String(model.sessionCleanupSummary.itemCount)))
                .font(.caption).foregroundColor(.secondary)
            Button(trashReminder.isEmptyingTrash ? L10n.text("正在清空…") : L10n.text("清空废纸篓…")) {
                trashReminder.requestEmptyTrash(model: model)
            }
                .font(.body.weight(.medium))
                .controlSize(.large)
                .disabled(!trashReminder.canEmptyTrash(model: model))
        }
        .multilineTextAlignment(.center)
        .help(L10n.text("统计本次打开软件后的成功清理量，重新扫描不清零；不含失败或跳过项。恢复区和废纸篓中的文件可能仍占空间。"))
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
        .font(.caption).foregroundColor(.secondary).monospacedDigit()
        .lineLimit(1)
    }

    private func elapsedText(from startedAt: Date, to current: Date) -> Text {
        let seconds = max(0, Int(current.timeIntervalSince(startedAt)))
        let duration = String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        return Text(L10n.text("扫描用时：{0}", duration))
    }

    private var scanCoverage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("一次扫描包含")).font(.headline)
            VStack(spacing: 0) {
                ForEach(ScanModuleID.allCases, id: \.self) { module in
                    moduleScopeRow(module)
                    if module != ScanModuleID.allCases.last { Divider() }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxHeight: .infinity)
        }
    }

    private func moduleScopeRow(_ module: ScanModuleID) -> some View {
        Button {
            model.openScanResult(module)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: module.icon).font(.title3).foregroundColor(module.color).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.resultDestinationTitle).fontWeight(.semibold)
                    Text(module.scopeDetail).font(.caption).foregroundColor(.secondary)
                        .lineLimit(1).help(module.scopeDetail)
                }
                Spacer(minLength: 12)
                if let summary = model.defaultCleanupSummary(for: module) {
                    Text(L10n.text("清理 {0} 项 · {1}", String(summary.itemCount),
                        ByteCountFormatter.cleanerString(bytes: summary.bytes)))
                        .font(.caption.weight(.medium)).foregroundColor(.secondary)
                        .monospacedDigit().lineLimit(1)
                }
                HStack {
                    if let status = model.scanProgressByModule[module] {
                        ScanModuleStateView(state: status.state)
                    }
                }
                .frame(width: 150, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .frame(minHeight: 40, maxHeight: .infinity)
            .background(hoveredModule == module ? Color.accentColor.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredModule = $0 ? module : nil }
        .accessibilityHint(L10n.text("打开{0}扫描结果", module.resultDestinationTitle))
    }

    private var preScanTrust: some View {
        HStack(spacing: 12) {
            TrustItem(icon: "eye", title: L10n.text("扫描可解释"), detail: L10n.text("每项都显示路径和发现依据"))
            TrustItem(icon: "play.circle", title: L10n.text("删除前检查"), detail: L10n.text("自动复验，跳过变化或占用项"))
            TrustItem(icon: "arrow.uturn.backward.circle", title: L10n.text("默认可恢复"), detail: L10n.text("删除后可恢复，恢复不覆盖原文件"))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

}

private struct ScanButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? .white : .secondary)
            .background(isEnabled ? Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)
                : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? Color.accentColor : .clear, lineWidth: 2)
                    .padding(-3).allowsHitTesting(false)
            }
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
            Image(systemName: icon).foregroundStyle(.tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption).foregroundColor(.secondary).lineLimit(1).help(detail)
            }
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        case .localAIModels: L10n.text("识别本地模型与下载缓存，保留共享存储关系")
        case .projects: L10n.text("按源码工程识别依赖、构建输出与项目活动")
        }
    }

    var title: String {
        switch self { case .general: L10n.text("系统清理"); case .applications: L10n.text("应用"); case .largeFiles: L10n.text("重复大文件"); case .agentEnvironment: L10n.text("Agent 环境"); case .localAIModels: L10n.text("本地 AI 模型"); case .projects: L10n.text("项目产物") }
    }
    var icon: String {
        switch self { case .general: "trash"; case .applications: "app.dashed"; case .largeFiles: "doc.text.magnifyingglass"; case .agentEnvironment: "terminal"; case .localAIModels: "brain"; case .projects: "shippingbox" }
    }
    var color: Color {
        switch self { case .general: .green; case .applications: .blue; case .largeFiles: .orange; case .agentEnvironment: .purple; case .localAIModels: .indigo; case .projects: .teal }
    }
    var resultDestinationTitle: String {
        switch self { case .general: L10n.text("系统清理"); case .applications: L10n.text("应用卸载"); case .largeFiles: L10n.text("重复大文件"); case .agentEnvironment: L10n.text("Agent 环境"); case .localAIModels: L10n.text("本地 AI 模型"); case .projects: L10n.text("项目产物") }
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
