import AppKit
import CleanerCore
import SwiftUI
import XCTest
@testable import CleanerApp

final class UninstallReadOnlyRowsTests: XCTestCase {
    @MainActor
    func testExpandedFileAndReceiptRowsHaveNoSelectionControls() throws {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: "/Applications/Fixture.app")
        let candidate = CleanupCandidate(url: url, displayName: "Fixture", category: .application,
            bytes: 100, risk: .review, evidence: [], identity: .init(device: 1, inode: 1, size: 100, modificationTime: 1, kind: .directory),
            source: .application, lastAccessDate: nil, isActive: false)
        let host = NSHostingView(rootView: VStack {
            UninstallItemRow(item: .init(candidate: candidate, containsUserData: false, isShared: false))
            UninstallReceiptRow(receipt: URL(fileURLWithPath: "/private/var/db/receipts/org.example.fixture.bom"))
        })
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 900, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = host
        host.frame = .init(x: 0, y: 0, width: 900, height: 150)
        host.layoutSubtreeIfNeeded()
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        XCTAssertFalse(descendants(host).contains { $0 is NSButton }, "Only the application row controls uninstall selection")
    }
}
