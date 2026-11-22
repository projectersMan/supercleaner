import AppKit
import CleanerCore
import Combine
import Foundation
import SwiftUI

struct TrashEmptyingConfirmation {
    let shouldEmptyTrash: Bool
    let suppressReminders: Bool
}

@MainActor final class TrashReminderController: ObservableObject {
    private var state: TrashReminderState
    private var isPresenting = false
    private var lastEmptiedSummary: CleanupSessionSummary?
    private var pendingCloseReminder: AnyCancellable?
    private var terminationObservation: AnyCancellable?
    private var applicationIsTerminating = false
    @Published private(set) var isEmptyingTrash = false
    private(set) var emptyingTask: Task<Bool, Never>?
    private let confirmEmptyTrash: @MainActor (Bool) -> TrashEmptyingConfirmation
    private let emptyTrash: @Sendable () async throws -> Void
    private let reportFailure: @MainActor (String) -> Void

    convenience init(preferences: UserDefaults) {
        self.init(preferences: preferences, confirmEmptyTrash: Self.confirmEmptying,
                  emptyTrash: FinderTrashEmptying.execute, reportFailure: Self.presentFailure)
    }

    init(preferences: UserDefaults, confirmEmptyTrash: @escaping @MainActor (Bool) -> TrashEmptyingConfirmation,
         emptyTrash: @escaping @Sendable () async throws -> Void, reportFailure: @escaping @MainActor (String) -> Void) {
        state = TrashReminderState(preferences: preferences)
        self.confirmEmptyTrash = confirmEmptyTrash
        self.emptyTrash = emptyTrash
        self.reportFailure = reportFailure
        terminationObservation = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.applicationIsTerminating = true
                self?.pendingCloseReminder = nil
            }
    }

    func shouldRemind(cleanedBytes: UInt64) -> Bool { state.shouldRemind(cleanedBytes: cleanedBytes) }

    func canEmptyTrash(model: AppModel) -> Bool {
        !isPresenting && !isEmptyingTrash && model.canBeginTrashEmptying
            && lastEmptiedSummary != model.sessionCleanupSummary
    }

    @discardableResult func requestEmptyTrash(model: AppModel) -> Task<Bool, Never> {
        requestEmptyTrash(model: model, showsSuppressionOption: false)
    }

    private func requestEmptyTrash(model: AppModel, showsSuppressionOption: Bool) -> Task<Bool, Never> {
        guard canEmptyTrash(model: model), model.beginTrashEmptying() else { return Task { false } }
        pendingCloseReminder = nil
        let capturedSummary = model.sessionCleanupSummary
        let cleanedBytes = capturedSummary.bytes
        isPresenting = true
        let confirmation = confirmEmptyTrash(showsSuppressionOption)
        isPresenting = false
        if showsSuppressionOption && confirmation.suppressReminders { state.setRemindersSuppressed(true) }
        guard confirmation.shouldEmptyTrash else {
            model.cancelTrashEmptyingConfirmation()
            return Task { false }
        }
        isEmptyingTrash = true
        let operation = Task { try await emptyTrash() }
        emptyingTask = Task {
            let result = await operation.result
            if case .success = result {
                state.recordTrashEmptied(cleanedBytes: cleanedBytes)
                lastEmptiedSummary = capturedSummary
            }
            await model.finishTrashEmptying()
            isEmptyingTrash = false
            emptyingTask = nil
            if case let .failure(error) = result {
                isPresenting = true
                defer { isPresenting = false }
                reportFailure(Self.failureDescription(error))
                return false
            }
            return true
        }
        return emptyingTask!
    }

    static func makeEmptyingAlert(showsSuppressionOption: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("要永久清空废纸篓吗？")
        alert.informativeText = L10n.text("废纸篓中的所有项目都将永久删除，无法恢复。此操作由 Finder 执行，可能需要授权。")
        alert.showsSuppressionButton = showsSuppressionOption
        if showsSuppressionOption { alert.suppressionButton?.title = L10n.text("不再提醒") }
        let cancel = alert.addButton(withTitle: L10n.text("取消"))
        cancel.keyEquivalent = "\u{1b}"
        let empty = alert.addButton(withTitle: L10n.text("清空废纸篓"))
        empty.keyEquivalent = ""
        // Return and Escape both keep the irreversible operation cancelled.
        alert.window.defaultButtonCell = cancel.cell as? NSButtonCell
        return alert
    }

    static func confirmEmptying(showsSuppressionOption: Bool) -> TrashEmptyingConfirmation {
        let alert = makeEmptyingAlert(showsSuppressionOption: showsSuppressionOption)
        let approved = alert.runModal() == .alertSecondButtonReturn
        return TrashEmptyingConfirmation(shouldEmptyTrash: approved,
            suppressReminders: showsSuppressionOption && alert.suppressionButton?.state == .on)
    }

    private static func presentFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("未能确认废纸篓已清空")
        alert.informativeText = message
        alert.addButton(withTitle: L10n.text("好"))
        alert.runModal()
    }

    private static func failureDescription(_ error: Error) -> String {
        if let processFailure = error as? ProcessFailure {
            switch processFailure {
            case .timedOut: return L10n.text("清空废纸篓超时。请在 Finder 中检查剩余项目；未记录清空成功。")
            case .cancelled: return L10n.text("清空废纸篓已取消。请在 Finder 中检查剩余项目；未记录清空成功。")
            case .outputLimit: return L10n.text("Finder 返回的信息超出安全限制。请检查废纸篓；未记录清空成功。")
            }
        }
        return L10n.text("清空废纸篓失败：{0}。请在 Finder 中检查剩余项目；未记录清空成功。", error.localizedDescription)
    }

    @discardableResult func remindIfNeeded(model: AppModel) -> Task<Bool, Never>? {
        guard canEmptyTrash(model: model), state.shouldRemind(cleanedBytes: model.sessionCleanupSummary.bytes) else { return nil }
        return requestEmptyTrash(model: model)
    }

    func remindAfterWindowClose(model: AppModel) {
        guard !applicationIsTerminating, !isPresenting, !isEmptyingTrash, !model.trashEmptyingInProgress else { return }
        // A closed window cannot display its completed result sheet. The model
        // keeps execution protected and only dismisses results after it finishes.
        if model.showsDeletionSheet { model.dismissDeletionSheet() }
        if model.canBeginTrashEmptying {
            pendingCloseReminder = nil
            if state.shouldRemind(cleanedBytes: model.sessionCleanupSummary.bytes) {
                _ = requestEmptyTrash(model: model, showsSuppressionOption: true)
            }
            return
        }
        guard pendingCloseReminder == nil else { return }
        // Keep the close request in the session controller even after its view
        // disappears. Published changes arrive before the new values are set.
        pendingCloseReminder = model.objectWillChange.merge(with: model.helper.objectWillChange)
            .receive(on: RunLoop.main).sink { [weak self, weak model] _ in
                guard let self, let model else { return }
                self.remindAfterWindowClose(model: model)
            }
    }
}

enum FinderTrashEmptyingError: Error, LocalizedError {
    case failed(status: Int32, message: String)
    case unconfirmed

    var errorDescription: String? {
        switch self {
        case let .failed(status, message): L10n.text("Finder 操作失败（退出码 {0}）：{1}", String(status), message)
        case .unconfirmed: L10n.text("Finder 尚未确认废纸篓为空")
        }
    }
}

enum FinderTrashEmptying {
    static let confirmationScript = """
    tell application id "com.apple.finder"
        if (count of items of trash) is 0 then return "SUPERCLEANER_TRASH_EMPTY_CONFIRMED"
        return "SUPERCLEANER_TRASH_NOT_EMPTY"
    end tell
    """
    // Finder's empty command may return before background deletion completes.
    // Read Finder's combined Trash after the command and require an empty result.
    static let script = """
    with timeout of 120 seconds
        tell application id "com.apple.finder"
            if (count of items of trash) is 0 then return "SUPERCLEANER_TRASH_EMPTY_CONFIRMED"
            empty trash
            repeat 240 times
                if (count of items of trash) is 0 then return "SUPERCLEANER_TRASH_EMPTY_CONFIRMED"
                delay 0.5
            end repeat
            error "Finder has not confirmed that Trash is empty" number -2700
        end tell
    end timeout
    """

    static func execute() async throws {
        try await execute(using: runScript)
    }

    static func execute(using run: @Sendable (String) async throws -> (status: Int32, stdout: Data, stderr: Data)) async throws {
        let output = try await run(script)
        // Trash may become empty after the precheck (Finder or another app).
        // An error code alone is never success: independently confirm the target state.
        if output.status != 0 {
            let confirmation = try await run(confirmationScript)
            if confirmation.status == 0,
               String(decoding: confirmation.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                == "SUPERCLEANER_TRASH_EMPTY_CONFIRMED" { return }
        }
        try validate(status: output.status, stdout: output.stdout, stderr: output.stderr)
    }

    private static func runScript(_ script: String) async throws -> (status: Int32, stdout: Data, stderr: Data) {
        let output = try await BoundedProcess.run("/usr/bin/osascript", arguments: ["-e", script],
            timeout: script == confirmationScript ? 5 : 125, maximumOutputBytes: 65_536)
        return (output.status, output.stdout, output.stderr)
    }

    static func validate(status: Int32, stdout: Data, stderr: Data) throws {
        guard status == 0 else {
            throw FinderTrashEmptyingError.failed(status: status,
                message: String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "SUPERCLEANER_TRASH_EMPTY_CONFIRMED" else {
            throw FinderTrashEmptyingError.unconfirmed
        }
    }
}
