import AppKit
import CleanerCore
import Combine
import Foundation
import SwiftUI

// Only the controller/observer contract is needed. This fixture does not scan,
// read disk capacity, invoke Finder, alter the real Trash, or recreate sessions.
@MainActor final class HelperFixture: ObservableObject {
    @Published var isChanging = false
}

@MainActor final class AppModel: ObservableObject {
    @Published var sessionCleanupSummary = CleanupSessionSummary()
    @Published var isBusy = false
    @Published var showsDeletionSheet = false
    @Published var isScanRunning = false
    let helper = HelperFixture()
    private(set) var trashEmptyingInProgress = false
    private(set) var capacityReads = 0
    var canBeginTrashEmptying: Bool { !trashEmptyingInProgress && !isBusy && !showsDeletionSheet && !helper.isChanging }

    func dismissDeletionSheet() {
        guard !isBusy else { return }
        showsDeletionSheet = false
    }

    func beginTrashEmptying() -> Bool {
        guard canBeginTrashEmptying else { return false }
        trashEmptyingInProgress = true
        return true
    }

    func cancelTrashEmptyingConfirmation() { trashEmptyingInProgress = false }

    func finishTrashEmptying() async {
        capacityReads += 1
        trashEmptyingInProgress = false
    }
}

actor ForbiddenTrashExecution {
    func execute() async throws {
        preconditionFailure("This Cancel-only UI fixture must never execute Trash emptying")
    }
}

@MainActor final class ExistingWindowDelegate: NSObject, NSWindowDelegate {
    private(set) var closeRequests = 0

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeRequests += 1
        return true
    }
}

@MainActor final class ExactTrashConfirmationProbe {
    var expectsSuppressionOption = false
    var choosesSuppression = false
    private(set) var confirmationCount = 0
    private(set) var buttonTitles: [[String]] = []

    func confirm(showsSuppressionOption: Bool) -> TrashEmptyingConfirmation {
        FileHandle.standardOutput.write(Data("CONFIRM: closeOption=\(showsSuppressionOption), priorCount=\(confirmationCount)\n".utf8))
        precondition(showsSuppressionOption == expectsSuppressionOption)
        let alert = TrashReminderController.makeEmptyingAlert(showsSuppressionOption: showsSuppressionOption)
        precondition(alert.alertStyle == .warning)
        precondition(alert.messageText == L10n.text("要永久清空废纸篓吗？"))
        precondition(alert.informativeText == L10n.text("废纸篓中的所有项目都将永久删除，无法恢复。此操作由 Finder 执行，可能需要授权。"))
        let titles = alert.buttons.map(\.title)
        precondition(titles == [L10n.text("取消"), L10n.text("清空废纸篓")])
        precondition(alert.showsSuppressionButton == expectsSuppressionOption, "only the window-close reminder must offer Don't remind again")
        // AppKit may normalize Cancel's Escape key to Return when its cell
        // becomes the default. Verify the safe default button by identity.
        precondition(alert.buttons[1].keyEquivalent.isEmpty)
        precondition(alert.buttons[1].isEnabled, "a displayed Trash confirmation must offer an enabled Empty Trash action")
        precondition(alert.window.defaultButtonCell === alert.buttons[0].cell)
        confirmationCount += 1
        buttonTitles.append(titles)
        if CommandLine.arguments.contains("--modal-preview") {
            return TrashReminderController.confirmEmptying(showsSuppressionOption: showsSuppressionOption)
        }
        if showsSuppressionOption {
            precondition(alert.suppressionButton?.title == L10n.text("不再提醒"))
            alert.suppressionButton!.state = choosesSuppression ? .on : .off
        }
        return TrashEmptyingConfirmation(shouldEmptyTrash: false,
            suppressReminders: showsSuppressionOption && alert.suppressionButton?.state == .on)
    }

    func reportFailure(_ message: String) {
        preconditionFailure("Cancel must not produce an execution failure: \(message)")
    }
}

struct CloseReminderTestRoot: View {
    @ObservedObject var model: AppModel
    let controller: TrashReminderController

    var body: some View {
        Text(String(model.sessionCleanupSummary.bytes))
            .background(TrashReminderWindowObserver(model: model, controller: controller))
    }
}

@MainActor final class ExactTrashDialogHarness: NSObject, NSApplicationDelegate {
    private let domain = "SuperCleaner.ExactTrashDialog.\(UUID())"
    private let model = AppModel()
    private let probe = ExactTrashConfirmationProbe()
    private let executor = ForbiddenTrashExecution()
    private let windowDelegate = ExistingWindowDelegate()
    private var preferences: UserDefaults!
    private var controller: TrashReminderController!
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
    )

    override init() {
        super.init()
        preferences = UserDefaults(suiteName: domain)!
        preferences.removePersistentDomain(forName: domain)
        controller = TrashReminderController(preferences: preferences, confirmEmptyTrash: probe.confirm,
            emptyTrash: executor.execute, reportFailure: probe.reportFailure)
        window.title = "SuperCleaner Exact Trash Dialog Check"
        window.isReleasedWhenClosed = false
        window.delegate = windowDelegate
        window.contentView = NSHostingView(rootView: CloseReminderTestRoot(model: model, controller: controller))
        window.contentView!.layoutSubtreeIfNeeded()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let action = CommandLine.arguments.contains("--modal-preview") ? #selector(previewScanningClose) : #selector(runChecks)
        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: action, userInfo: nil, repeats: false)
    }

    @objc private func previewScanningClose() {
        model.sessionCleanupSummary = CleanupSessionSummary(itemCount: 1, bytes: 299_000_000)
        model.isScanRunning = true
        probe.expectsSuppressionOption = true
        window.makeKeyAndOrderFront(nil)
        window.contentView!.layoutSubtreeIfNeeded()
        window.standardWindowButton(.closeButton)!.performClick(nil)
        precondition(!window.isVisible && model.isScanRunning && !model.trashEmptyingInProgress)
        precondition(preferences.bool(forKey: TrashReminderState.suppressionPreferenceKey))
        precondition(model.capacityReads == 0 && model.sessionCleanupSummary.bytes == 299_000_000)
        preferences.removePersistentDomain(forName: domain)
        print("PASS: production modal checkbox + Cancel persisted test-only suppression while scanning/session continued; forbidden executor never called")
        exit(EXIT_SUCCESS)
    }

    @objc private func runChecks() {
        defer { preferences.removePersistentDomain(forName: domain) }
        window.makeKeyAndOrderFront(nil)
        window.standardWindowButton(.closeButton)!.performClick(nil)
        precondition(!window.isVisible && probe.confirmationCount == 0)
        print("PASS: actual red close button skips the dialog at zero cleanup bytes")

        model.sessionCleanupSummary = CleanupSessionSummary(itemCount: 1, bytes: 1_024)
        controller.requestEmptyTrash(model: model)
        precondition(probe.confirmationCount == 1 && !model.trashEmptyingInProgress)
        print("PASS: dashboard entry uses exactly Cancel / Empty Trash and no suppression option")

        window.makeKeyAndOrderFront(nil)
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.close()
        precondition(probe.confirmationCount == 1)
        print("PASS: closing an unrelated panel does not request the Trash dialog")

        probe.expectsSuppressionOption = true
        window.standardWindowButton(.closeButton)!.performClick(nil)
        precondition(!window.isVisible && probe.confirmationCount == 2)
        precondition(window.delegate === windowDelegate && windowDelegate.closeRequests == 2)
        precondition((window.contentView as! NSHostingView<CloseReminderTestRoot>).rootView.model === model)
        precondition(!model.trashEmptyingInProgress && model.capacityReads == 0)
        precondition(controller.shouldRemind(cleanedBytes: 1_024))
        precondition(!preferences.bool(forKey: "cleanup.suppressTrashReminder"))
        precondition(probe.buttonTitles[0] == probe.buttonTitles[1])
        print("PASS: red close invokes the same dialog factory and buttons; Cancel leaves the app session in the background with its reminder intact")
        print("PASS: the existing NSWindow delegate and scan model are retained; no Finder commands were sent")
        model.isBusy = true
        model.sessionCleanupSummary = CleanupSessionSummary()
        window.makeKeyAndOrderFront(nil)
        window.standardWindowButton(.closeButton)!.performClick(nil)
        window.makeKeyAndOrderFront(nil)
        window.standardWindowButton(.closeButton)!.performClick(nil)
        precondition(probe.confirmationCount == 2)
        model.sessionCleanupSummary = CleanupSessionSummary(itemCount: 2, bytes: 2_048)
        model.showsDeletionSheet = true
        model.isBusy = false
        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(checkDeferredReminder), userInfo: nil, repeats: false)
    }

    @objc private func checkDeferredReminder() {
        precondition(probe.confirmationCount == 3, "close during cleanup finalization must defer exactly one reminder until the model is idle")
        precondition(!model.trashEmptyingInProgress && model.capacityReads == 0)
        precondition(!model.showsDeletionSheet, "a completed result sheet must not block a reminder after its window closes")
        precondition(window.delegate === windowDelegate)
        print("PASS: repeated red close during cleanup finalization retains exactly one reminder after delayed cleanup accounting")
        model.isBusy = true
        model.sessionCleanupSummary = CleanupSessionSummary()
        window.makeKeyAndOrderFront(nil)
        window.standardWindowButton(.closeButton)!.performClick(nil)
        model.isBusy = false
        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(checkZeroCleanup), userInfo: nil, repeats: false)
    }

    @objc private func checkZeroCleanup() {
        precondition(probe.confirmationCount == 3, "idle without successful cleanup must not prompt")
        print("PASS: a deferred close with no successful cleanup produces no dialog")
        model.helper.isChanging = true
        model.sessionCleanupSummary = CleanupSessionSummary(itemCount: 3, bytes: 3_072)
        window.makeKeyAndOrderFront(nil)
        window.standardWindowButton(.closeButton)!.performClick(nil)
        precondition(probe.confirmationCount == 3)
        model.helper.isChanging = false
        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(checkHelperCompletion), userInfo: nil, repeats: false)
    }

    @objc private func checkHelperCompletion() {
        precondition(probe.confirmationCount == 4, "Helper-only state changes must wake the pending close reminder")
        precondition(!model.trashEmptyingInProgress && model.capacityReads == 0)
        print("PASS: independent Helper completion wakes the pending close without a parent model change")
        model.isScanRunning = true
        window.makeKeyAndOrderFront(nil)
        window.contentView!.layoutSubtreeIfNeeded()
        window.standardWindowButton(.closeButton)!.performClick(nil)
        precondition(probe.confirmationCount == 5)
        precondition(model.isScanRunning && !model.trashEmptyingInProgress)
        print("PASS: actual hosted SwiftUI close prompts while scanning continues and its Empty Trash action is enabled")
        probe.choosesSuppression = true
        window.makeKeyAndOrderFront(nil)
        window.standardWindowButton(.closeButton)!.performClick(nil)
        precondition(probe.confirmationCount == 6)
        precondition(!TrashReminderState(preferences: UserDefaults(suiteName: domain)!).shouldRemind(cleanedBytes: UInt64.max))
        window.makeKeyAndOrderFront(nil)
        window.standardWindowButton(.closeButton)!.performClick(nil)
        precondition(probe.confirmationCount == 6)
        model.isScanRunning = false
        probe.expectsSuppressionOption = false
        controller.requestEmptyTrash(model: model)
        precondition(probe.confirmationCount == 7)
        precondition(preferences.bool(forKey: TrashReminderState.suppressionPreferenceKey))
        print("PASS: Don't remind again persists and skips later closes; manual Empty Trash still confirms without that option")
        TrashReminderState(preferences: preferences).setRemindersSuppressed(false)
        probe.choosesSuppression = false
        probe.expectsSuppressionOption = true
        window.makeKeyAndOrderFront(nil)
        window.standardWindowButton(.closeButton)!.performClick(nil)
        precondition(probe.confirmationCount == 8 && controller.shouldRemind(cleanedBytes: 3_072))
        precondition(model.capacityReads == 0 && model.sessionCleanupSummary.bytes == 3_072)
        print("PASS: restoring the same preference re-enables close reminders without faking emptying or changing cleanup accounting")
        preferences.removePersistentDomain(forName: domain)
        exit(EXIT_SUCCESS)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(CommandLine.arguments.contains("--modal-preview") ? .regular : .accessory)
let harness = ExactTrashDialogHarness()
application.delegate = harness
application.run()
