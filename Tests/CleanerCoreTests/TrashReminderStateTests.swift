import Foundation
import XCTest
@testable import CleanerCore

final class TrashReminderStateTests: XCTestCase {
    func testOnlyPositiveCleanupBytesRequireReminder() {
        let domain = "TrashReminderStateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        let state = TrashReminderState(preferences: preferences)

        XCTAssertFalse(state.shouldRemind(cleanedBytes: 0))
        XCTAssertTrue(state.shouldRemind(cleanedBytes: 1))
        XCTAssertTrue(state.shouldRemind(cleanedBytes: UInt64.max))
    }

    func testAcknowledgementAvoidsDuplicateWindowAndQuitRemindersUntilMoreCleanup() {
        let domain = "TrashReminderStateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        var state = TrashReminderState(preferences: preferences)

        state.acknowledge(cleanedBytes: 1_024, suppressReminders: false)

        XCTAssertFalse(state.shouldRemind(cleanedBytes: 0))
        XCTAssertFalse(state.shouldRemind(cleanedBytes: 1_024))
        XCTAssertTrue(state.shouldRemind(cleanedBytes: 1_025))
        XCTAssertTrue(TrashReminderState(preferences: preferences).shouldRemind(cleanedBytes: 1_024))
    }

    func testSuppressionPersistsWhenPreferencesAreReopened() {
        let domain = "TrashReminderStateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        var state = TrashReminderState(preferences: preferences)

        state.acknowledge(cleanedBytes: 1_024, suppressReminders: true)

        let reopened = TrashReminderState(preferences: UserDefaults(suiteName: domain)!)
        XCTAssertFalse(state.shouldRemind(cleanedBytes: 2_048))
        XCTAssertFalse(reopened.shouldRemind(cleanedBytes: 1))
        XCTAssertFalse(reopened.shouldRemind(cleanedBytes: UInt64.max))
    }
}
