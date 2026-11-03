import AppKit
import SwiftUI

/// Let the native full-height sidebar draw continuously through the titlebar.
struct SidebarToolbarAlignment: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarToolbarAlignmentView { SidebarToolbarAlignmentView() }
    func updateNSView(_ nsView: SidebarToolbarAlignmentView, context: Context) { nsView.alignToolbar() }
}

final class SidebarToolbarAlignmentView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        alignToolbar()
    }

    func alignToolbar() {
        window?.titlebarAppearsTransparent = true
    }
}
