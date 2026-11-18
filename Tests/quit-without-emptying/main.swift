import AppKit
import CleanerCore
import Foundation

// The update subsystem is outside this isolated quit regression. The actual
// delegate, Trash controller and window observer are compiled by the script.
@MainActor enum ApplicationUpdateTerminationGuard {
    static var allowsTermination = true
}

@MainActor final class QuitWithoutEmptyingFixture: NSObject {
    private let model = AppModel()
    private let probe = ExactTrashConfirmationProbe()
    private let executor = ForbiddenTrashExecution()
    private let domain = "SuperCleaner.QuitWithoutEmptying.\(UUID())"
    private let hasCleanup = !CommandLine.arguments.contains("--no-cleanup")
    private var preferences: UserDefaults!
    private var controller: TrashReminderController!
    private var delegate: CleanerApplicationDelegate!
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)

    override init() {
        super.init()
        preferences = UserDefaults(suiteName: domain)!
        preferences.removePersistentDomain(forName: domain)
        controller = TrashReminderController(preferences: preferences, confirmEmptyTrash: probe.confirm,
            emptyTrash: executor.execute, reportFailure: probe.reportFailure)
        delegate = CleanerApplicationDelegate(trashReminder: controller)
        delegate.model = model
        NSApplication.shared.delegate = delegate
        if hasCleanup { model.sessionCleanupSummary = CleanupSessionSummary(itemCount: 1, bytes: 1_024) }
        window.isReleasedWhenClosed = false
        window.title = "SuperCleaner Cancel and Quit Regression"
        let observer = TrashReminderWindowView()
        observer.model = model
        observer.controller = controller
        window.contentView = observer
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate),
            name: NSApplication.willTerminateNotification, object: NSApplication.shared)
    }

    func start() {
        window.makeKeyAndOrderFront(nil)
        Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(requestQuit), userInfo: nil, repeats: false)
        Timer.scheduledTimer(timeInterval: 3, target: self, selector: #selector(timedOut), userInfo: nil, repeats: false)
    }

    @objc private func requestQuit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func willTerminate() {
        precondition(probe.confirmationCount == (hasCleanup ? 1 : 0), "quit must confirm at most once")
        precondition(!model.trashEmptyingInProgress && model.capacityReads == 0)
        precondition(model.sessionCleanupSummary.bytes == (hasCleanup ? 1_024 : 0))
        precondition(!preferences.bool(forKey: "cleanup.suppressTrashReminder"))
        precondition(delegate.terminationTask == nil)
        preferences.removePersistentDomain(forName: domain)
        FileHandle.standardOutput.write(Data("PASS: actual NSApplication will terminate, cleanup=\(hasCleanup), confirmations=\(probe.confirmationCount); no Finder execution, capacity read or cleanup accounting change\n".utf8))
    }

    @objc private func timedOut() {
        preferences.removePersistentDomain(forName: domain)
        FileHandle.standardError.write(Data("FAIL: Cancel left the actual NSApplication running instead of allowing quit\n".utf8))
        exit(EXIT_FAILURE)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let fixture = QuitWithoutEmptyingFixture()
fixture.start()
application.run()
