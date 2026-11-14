import AppKit
import SwiftUI

struct TrashReminderWindowObserver: NSViewRepresentable {
    let model: AppModel
    let controller: TrashReminderController

    func makeNSView(context: Context) -> TrashReminderWindowView {
        let view = TrashReminderWindowView()
        view.model = model
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: TrashReminderWindowView, context: Context) {
        nsView.model = model
        nsView.controller = controller
    }
}

final class TrashReminderWindowView: NSView {
    weak var model: AppModel?
    weak var controller: TrashReminderController?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let model else { return }
        controller?.remindIfNeeded(cleanedBytes: model.sessionCleanupSummary.bytes, isQuitting: false)
    }
}
