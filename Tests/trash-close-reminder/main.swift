import AppKit
import CleanerCore
import Foundation

// The bridge only reads this value. Keep scan/bootstrap side effects out of this UI fixture.
@MainActor final class AppModel {
    var sessionCleanupSummary = CleanupSessionSummary()
}

@MainActor final class TrashReminderHarness: NSObject, NSApplicationDelegate {
    private let domain = "SuperCleaner.TrashReminderHarness"
    private let preferences: UserDefaults
    private let controller: TrashReminderController
    private let model = AppModel()
    private let log: FileHandle
    private var reminderCount = 0
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )

    init(log: FileHandle) {
        self.log = log
        preferences = UserDefaults(suiteName: domain)!
        preferences.removePersistentDomain(forName: domain)
        controller = TrashReminderController(preferences: preferences)
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowBecameKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil
        )
        window.title = "SuperCleaner — Trash Reminder Verification"
        window.isReleasedWhenClosed = false
        let observer = TrashReminderWindowView()
        observer.model = model
        observer.controller = controller
        window.contentView = observer
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(runChecks), userInfo: nil, repeats: false)
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        guard let shownWindow = notification.object as? NSWindow, shownWindow !== window else { return }
        reminderCount += 1
    }

    @objc private func runChecks() {
        window.performClose(nil)
        precondition(!window.isVisible && reminderCount == 0)
        report("PASS: zero-byte main-window close has no reminder")

        model.sessionCleanupSummary = CleanupSessionSummary(itemCount: 2, bytes: 3_200_000_000)
        window.makeKeyAndOrderFront(nil)
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.close()
        precondition(reminderCount == 0)
        report("PASS: panel close has no reminder")

        report("ACTION: close reminder; select Open Trash to verify the Finder handoff")
        window.performClose(nil)
        precondition(!window.isVisible && reminderCount == 1)
        report("PASS: positive-byte window close completes after reminder")

        controller.remindIfNeeded(cleanedBytes: model.sessionCleanupSummary.bytes, isQuitting: true)
        window.makeKeyAndOrderFront(nil)
        window.performClose(nil)
        precondition(!window.isVisible && reminderCount == 1)
        report("PASS: unchanged cleanup amount skips duplicate quit and window reminders")

        model.sessionCleanupSummary = CleanupSessionSummary(itemCount: 3, bytes: 4_200_000_000)
        report("ACTION: new cleanup; check Don't remind me again and select Close Window")
        window.makeKeyAndOrderFront(nil)
        window.performClose(nil)
        precondition(!window.isVisible && reminderCount == 2)

        precondition(preferences.bool(forKey: "cleanup.suppressTrashReminder"), "The suppression checkbox must be selected")
        let reopened = TrashReminderController(preferences: UserDefaults(suiteName: domain)!)
        reopened.remindIfNeeded(cleanedBytes: UInt64.max, isQuitting: true)
        precondition(reminderCount == 2)
        preferences.removePersistentDomain(forName: domain)
        report("PASS: persisted suppression skips a fresh controller after further cleanup")
        report("PASS: native Trash reminder interaction checks complete")
        window.title = "PASS — Trash reminder checks complete"
        window.contentView = NSTextField(labelWithString: "PASS: close reminder, Finder handoff, and persistent suppression")
        window.makeKeyAndOrderFront(nil)
    }

    private func report(_ message: String) {
        log.write(Data("\(message)\n".utf8))
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
UserDefaults.standard.set(AppLanguage.simplifiedChinese.rawValue, forKey: AppLanguage.preferenceKey)
let logURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("native-ui.log")
precondition(FileManager.default.createFile(atPath: logURL.path, contents: Data()))
let log = try FileHandle(forWritingTo: logURL)
let harness = TrashReminderHarness(log: log)
application.delegate = harness
application.activate(ignoringOtherApps: true)
application.run()
