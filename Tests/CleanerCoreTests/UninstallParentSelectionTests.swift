import XCTest
@testable import CleanerCore

final class UninstallParentSelectionTests: XCTestCase {
    func testParentSelectsAndClearsFilesAndPairedReceiptsWithoutDeletingReceiptFiles() {
        let plan = plan("OneNote")
        let receipts = receipts("org.example.onenote")
        var files = UninstallBatchSelectionState()
        var packages = PackageReceiptCleanupSelection()
        files.toggle(plan: plan, receipts: receipts, receiptSelection: &packages)
        XCTAssertEqual(files.selectedItemIDs, plan.selectableItemIDs)
        XCTAssertTrue(packages.isSelected("org.example.onenote"))
        XCTAssertEqual(files.selectionState(for: plan, receipts: receipts, receiptSelection: packages), .all)
        XCTAssertEqual(files.selectedItems(in: [plan]).count, 2)
        XCTAssertEqual(files.summary(plans: [plan]).itemCount, 2)
        files.toggle(plan: plan, receipts: receipts, receiptSelection: &packages)
        XCTAssertTrue(files.selectedItemIDs.isEmpty)
        XCTAssertFalse(packages.isSelected("org.example.onenote"))
        XCTAssertEqual(files.selectionState(for: plan, receipts: receipts, receiptSelection: packages), .none)
    }

    func testPartialParentRestoresMissingReceiptOrOrdinaryChild() {
        let plan = plan("OneNote")
        let receipts = receipts("org.example.onenote")
        var files = UninstallBatchSelectionState(selectedItemIDs: plan.selectableItemIDs)
        var packages = PackageReceiptCleanupSelection()
        XCTAssertEqual(files.selectionState(for: plan, receipts: receipts, receiptSelection: packages), .partial)
        files.toggle(plan: plan, receipts: receipts, receiptSelection: &packages)
        XCTAssertEqual(files.selectedItemIDs, plan.selectableItemIDs)
        XCTAssertTrue(packages.isSelected("org.example.onenote"))
        files.toggle(item: plan.items[0])
        XCTAssertEqual(files.selectionState(for: plan, receipts: receipts, receiptSelection: packages), .partial)
        files.toggle(plan: plan, receipts: receipts, receiptSelection: &packages)
        XCTAssertEqual(files.selectionState(for: plan, receipts: receipts, receiptSelection: packages), .all)
    }

    func testSelectingOneApplicationLeavesOtherApplicationSelectionsIntact() {
        let first = plan("OneNote"), second = plan("Other")
        var files = UninstallBatchSelectionState()
        var packages = PackageReceiptCleanupSelection()
        files.toggle(plan: second, receipts: receipts("org.example.other"), receiptSelection: &packages)
        files.toggle(plan: first, receipts: receipts("org.example.onenote"), receiptSelection: &packages)
        files.toggle(plan: first, receipts: receipts("org.example.onenote"), receiptSelection: &packages)
        XCTAssertEqual(files.selectedItemIDs, second.selectableItemIDs)
        XCTAssertTrue(packages.isSelected("org.example.other"))
        XCTAssertFalse(packages.isSelected("org.example.onenote"))
    }

    func testApplicationsWithoutReceiptsKeepTheirExistingSelectAllBehavior() {
        let plan = plan("Other")
        var files = UninstallBatchSelectionState()
        var packages = PackageReceiptCleanupSelection()
        files.toggle(plan: plan, receipts: [], receiptSelection: &packages)
        XCTAssertEqual(files.selectionState(for: plan), .all)
        files.toggle(plan: plan)
        XCTAssertEqual(files.selectionState(for: plan), .none)
    }

    func testOnlySystemReceiptRowsForPackageInstallationsAreSelectable() {
        let valid = receipts("org.example.onenote")
        let invalid = URL(fileURLWithPath: "/tmp/org.example.onenote.plist")
        XCTAssertEqual(PackageReceiptCleanupSelection.selectableReceipts(
            for: .init(source: .packageInstaller, receipts: valid + [invalid])), valid)
        XCTAssertTrue(PackageReceiptCleanupSelection.selectableReceipts(for: .init(source: .homebrew, receipts: valid)).isEmpty)
        XCTAssertTrue(PackageReceiptCleanupSelection.selectableReceipts(for: nil).isEmpty)
    }

    private func receipts(_ packageID: String) -> [URL] {
        ["plist", "bom"].map { URL(fileURLWithPath: "/private/var/db/receipts/\(packageID).\($0)") }
    }

    private func plan(_ name: String) -> UninstallPlan {
        let app = InstalledApplication(bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleIdentifier: "org.example.\(name)", name: name, version: "1", isRunning: false, isSystem: false)
        let urls = [app.bundleURL, URL(fileURLWithPath: "/tmp/Library/Application Support/\(name)")]
        let items = urls.map { url in
            UninstallItem(candidate: .init(url: url, displayName: url.lastPathComponent, category: .application,
                bytes: 1, risk: .review, evidence: [],
                identity: .init(device: 1, inode: 1, size: 1, modificationTime: 1, kind: .directory),
                source: .application, lastAccessDate: nil, isActive: false), containsUserData: false, isShared: false)
        }
        return .init(application: app, items: items)
    }
}
