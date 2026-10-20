import CleanerCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("恢复已删除项目").font(.largeTitle.bold())
                Text("已删除项目可在保留期内恢复，期间仍占用磁盘空间。默认 24 小时后自动彻底删除，也可调整保留时间或立即彻底删除。")
                    .foregroundColor(.secondary)
            }
            .padding(24)
            Divider()

            if let message = model.recoveryMessage {
                HStack(spacing: 10) {
                    if model.recoveryActionReceiptID != nil { ProgressView().controlSize(.small) }
                    Image(systemName: model.recoveryMessageIsError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundColor(model.recoveryMessageIsError ? .orange : .accentColor)
                    Text(message).font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background((model.recoveryMessageIsError ? Color.orange : Color.accentColor).opacity(0.08))
                Divider()
            }

            if model.receipts.isEmpty {
                EmptyState(title: "还没有删除记录", message: "删除项目后，可在这里恢复或彻底删除。", icon: "clock.arrow.circlepath")
            } else {
                List(model.receipts) { receipt in
                    ReceiptRow(model: model, receipt: receipt)
                }
            }
        }
        .sheet(item: $model.restoreConfirmationReceipt) { receipt in
            RestoreConfirmationSheet(model: model, receipt: receipt)
        }
        .sheet(item: $model.purgeConfirmationReceipt) { receipt in
            PermanentDeletionSheet(model: model, receipt: receipt)
        }
    }
}

private struct ReceiptRow: View {
    @ObservedObject var model: AppModel
    let receipt: OperationReceipt

    private var quarantined: [OperationResult] { receipt.results.filter { $0.disposition == .quarantined } }
    private var restored: [OperationResult] { receipt.results.filter { $0.disposition == .restored } }
    private var trashed: [OperationResult] { receipt.results.filter { $0.disposition == .trashed } }
    private var deleted: [OperationResult] { receipt.results.filter { $0.disposition == .permanentlyDeleted } }
    private var unavailable: [OperationResult] { receipt.results.filter { $0.disposition == .unavailable } }
    private var quarantinedBytes: UInt64 { quarantined.reduce(0) { $0 + $1.bytes } }
    private var deletedBytes: UInt64 { deleted.reduce(0) { $0 + $1.bytes } }
    private var isWorking: Bool { model.recoveryActionReceiptID == receipt.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: statusIcon)
                    .font(.title2).foregroundColor(statusColor).frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(statusTitle).fontWeight(.semibold)
                        Text(receipt.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                    Text(summaryText).font(.caption).foregroundColor(.secondary)
                    if let reason = receipt.rejectionReason {
                        Text(reason).font(.caption).foregroundColor(.orange).lineLimit(2)
                    }
                }
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                    Text(model.recoveryActionKind == .purge ? "正在彻底删除" : "正在恢复")
                        .font(.caption).foregroundColor(.secondary)
                } else if !quarantined.isEmpty {
                    Button("恢复 \(quarantined.count) 项") { model.requestRestore(receipt) }
                        .help("恢复到原路径；若路径已有内容，将保存到相邻位置而不覆盖")
                    Button("彻底删除", role: .destructive) { model.requestPermanentDeletion(receipt) }
                        .foregroundColor(.red)
                        .help("仅彻底删除本应用保留的已删除项目；不可恢复")
                } else {
                    Label(resolvedTitle, systemImage: restored.isEmpty ? "trash.slash" : "arrow.uturn.backward.circle.fill")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            if !quarantined.isEmpty {
                Label("这 \(quarantined.count) 项仍占用约 \(ByteCountFormatter.cleanerString(bytes: quarantinedBytes))；恢复不会释放空间，彻底删除后才释放。", systemImage: "internaldrive")
                    .font(.caption).foregroundColor(.secondary).padding(.leading, 46)
                QuarantineScheduleControls(model: model, receipt: receipt)
                    .padding(.leading, 46)
            }
        }
        .padding(.vertical, 8)
    }

    private var summaryText: String {
        var parts: [String] = []
        if !quarantined.isEmpty { parts.append("可恢复 \(quarantined.count) 项 · \(ByteCountFormatter.cleanerString(bytes: quarantinedBytes))") }
        if !restored.isEmpty { parts.append("已恢复 \(restored.count) 项") }
        if !trashed.isEmpty { parts.append("已移入系统废纸篓 \(trashed.count) 项") }
        if !deleted.isEmpty { parts.append("已彻底删除 \(deleted.count) 项 · 释放约 \(ByteCountFormatter.cleanerString(bytes: deletedBytes))") }
        if !unavailable.isEmpty { parts.append("保留内容已不存在 \(unavailable.count) 项") }
        if parts.isEmpty { parts.append("未移动任何内容") }
        return parts.joined(separator: " · ")
    }

    private var resolvedTitle: String {
        if !restored.isEmpty, (!trashed.isEmpty || !deleted.isEmpty) { return "已恢复或删除" }
        if !restored.isEmpty { return "已恢复" }
        if !trashed.isEmpty { return "已移入系统废纸篓" }
        if !deleted.isEmpty { return "已彻底删除" }
        if !unavailable.isEmpty { return "保留内容已不存在" }
        return "没有可恢复内容"
    }

    private var statusTitle: String {
        switch receipt.overallStatus {
        case .completed: "删除操作已完成"
        case .partial: "删除操作部分完成"
        case .rejected: "删除操作已拒绝"
        case .failed: "删除操作失败"
        }
    }
    private var statusIcon: String { receipt.overallStatus == .completed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
    private var statusColor: Color { receipt.overallStatus == .completed ? .green : .orange }
}

private struct QuarantineScheduleControls: View {
    @ObservedObject var model: AppModel
    let receipt: OperationReceipt

    private var schedule: QuarantineSchedule? { model.quarantineSchedule(for: receipt.id) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: schedule?.policy == .manual ? "hand.raised.fill" : "timer")
                .foregroundColor(schedule?.failureMessage == nil ? .accentColor : .orange)
            if let schedule {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(countdownText(schedule: schedule, now: context.date))
                            .font(.caption.weight(.semibold))
                        if let deadline = schedule.scheduledDeletionAt {
                            Text("计划时间：\(deadline.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        if let failure = schedule.failureMessage {
                            Text("上次尝试失败：\(failure)")
                                .font(.caption2).foregroundColor(.orange).lineLimit(2)
                        }
                    }
                }
            } else {
                Text("正在建立自动删除计划…").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Picker(
                "保留时间",
                selection: Binding(
                    get: { schedule?.policy ?? model.defaultQuarantineRetentionPolicy },
                    set: { model.rescheduleQuarantine(receipt, policy: $0) }
                )
            ) {
                ForEach(
                    QuarantineRetentionPolicy.allCases.filter {
                        $0 != .immediate || schedule?.policy == .immediate
                    },
                    id: \.self
                ) { policy in
                    Text(policy.displayTitle).tag(policy)
                }
            }
            .pickerStyle(.menu).frame(width: 130)
            .disabled(schedule == nil || model.recoveryActionReceiptID != nil)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }

    private func countdownText(schedule: QuarantineSchedule, now: Date) -> String {
        let countdown = QuarantineCountdown(schedule: schedule, now: now)
        switch countdown.state {
        case .manual:
            return "手动保留，不会自动彻底删除"
        case .due:
            return schedule.policy == .immediate
                ? "等待 App 移入系统废纸篓"
                : "已到期，等待 App 完成彻底删除"
        case .scheduled:
            let seconds = Int(countdown.remainingSeconds)
            let days = seconds / 86_400
            let hours = (seconds % 86_400) / 3_600
            let minutes = max(1, (seconds % 3_600) / 60)
            if days > 0 { return "剩余 \(days) 天 \(hours) 小时后自动彻底删除" }
            if hours > 0 { return "剩余 \(hours) 小时 \(minutes) 分钟后自动彻底删除" }
            return "剩余约 \(minutes) 分钟后自动彻底删除"
        }
    }
}

private struct PermanentDeletionSheet: View {
    @ObservedObject var model: AppModel
    let receipt: OperationReceipt

    private var quarantined: [OperationResult] { receipt.results.filter { $0.disposition == .quarantined } }
    private var bytes: UInt64 { quarantined.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("彻底删除", systemImage: "trash.fill")
                .font(.title.bold()).foregroundColor(.red)
            Text("将永久删除本应用保留的已删除项目，共 \(quarantined.count) 项，释放约 \(ByteCountFormatter.cleanerString(bytes: bytes))。此操作不可恢复，也无法撤销。")
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            RecoveryItemList(items: quarantined)
            Label("仅彻底删除这条记录中保留的项目，不会处理原目录或相邻文件。", systemImage: "lock.shield")
                .font(.callout).foregroundColor(.secondary)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("取消") { model.dismissPermanentDeletion() }
                Spacer()
                Button("彻底删除", role: .destructive) { model.confirmPermanentDeletion() }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }
        .padding(24).frame(width: 560)
    }
}

private struct RestoreConfirmationSheet: View {
    @ObservedObject var model: AppModel
    let receipt: OperationReceipt

    private var quarantined: [OperationResult] { receipt.results.filter { $0.disposition == .quarantined } }
    private var bytes: UInt64 { quarantined.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("确认恢复", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.title.bold()).foregroundColor(.accentColor)
            Text("将恢复以下 \(quarantined.count) 项，共约 \(ByteCountFormatter.cleanerString(bytes: bytes))。如果原路径已有同名内容，会恢复到相邻位置，不会覆盖现有文件。")
                .foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            RecoveryItemList(items: quarantined)
            HStack {
                Button("取消") { model.dismissRestoreConfirmation() }
                Spacer()
                Button("确认恢复") { model.confirmRestore() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 620)
    }
}

private struct RecoveryItemList: View {
    let items: [OperationResult]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "doc")
                            .foregroundColor(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.originalURL.lastPathComponent)
                                .font(.callout.weight(.medium)).lineLimit(1)
                            Text(item.originalURL.path)
                                .font(.caption2.monospaced()).foregroundColor(.secondary)
                                .lineLimit(2).textSelection(.enabled)
                        }
                        Spacer(minLength: 12)
                        Text(ByteCountFormatter.cleanerString(bytes: item.bytes))
                            .font(.caption).foregroundColor(.secondary).fixedSize()
                    }
                    .padding(.vertical, 9)
                    if item.id != items.last?.id { Divider() }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(minHeight: 120, maxHeight: 260)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}
