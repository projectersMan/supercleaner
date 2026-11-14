import AppKit
import CleanerCore
import Foundation

@MainActor final class TrashReminderController {
    private var state: TrashReminderState
    private var isPresenting = false

    init(preferences: UserDefaults) {
        state = TrashReminderState(preferences: preferences)
    }

    func remindIfNeeded(cleanedBytes: UInt64, isQuitting: Bool) {
        guard !isPresenting, state.shouldRemind(cleanedBytes: cleanedBytes) else { return }
        isPresenting = true
        defer { isPresenting = false }

        let alert = NSAlert()
        alert.messageText = L10n.text("清空废纸篓，释放磁盘空间")
        alert.informativeText = L10n.text(
            "本次已清理 {0}，清空废纸篓以释放空间。",
            ByteCountFormatter.cleanerString(bytes: cleanedBytes)
        )
        alert.addButton(withTitle: L10n.text("打开废纸篓"))
        alert.addButton(withTitle: isQuitting ? L10n.text("继续退出") : L10n.text("直接关闭"))
            .keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L10n.text("不再提醒")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn || response == .alertSecondButtonReturn else { return }
        state.acknowledge(cleanedBytes: cleanedBytes, suppressReminders: alert.suppressionButton?.state == .on)
        guard response == .alertFirstButtonReturn else { return }

        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        guard NSWorkspace.shared.open(trash) else {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = L10n.text("无法打开废纸篓")
            failure.informativeText = L10n.text("请点击 Dock 中的废纸篓图标，检查内容后手动清空。")
            failure.addButton(withTitle: L10n.text("好"))
            failure.runModal()
            return
        }
    }
}
