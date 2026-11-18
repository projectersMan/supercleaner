import Foundation
import XCTest
@testable import CleanerCore

final class TrashReminderStateTests: XCTestCase {
    func testSuppressionCanBeRestoredWithoutAcknowledgingUnemptiedCleanup() {
        let domain = "TrashReminderStateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        let state = TrashReminderState(preferences: preferences)
        state.setRemindersSuppressed(true)
        XCTAssertFalse(state.shouldRemind(cleanedBytes: 1_024))
        state.setRemindersSuppressed(false)
        XCTAssertTrue(state.shouldRemind(cleanedBytes: 1_024))
        XCTAssertTrue(TrashReminderState(preferences: UserDefaults(suiteName: domain)!).shouldRemind(cleanedBytes: 1_024))
    }

    func testOnlyPositiveCleanupBytesRequireReminder() {
        let domain = "TrashReminderStateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        let state = TrashReminderState(preferences: preferences)

        XCTAssertFalse(state.shouldRemind(cleanedBytes: 0))
        XCTAssertTrue(state.shouldRemind(cleanedBytes: 1))
        XCTAssertTrue(state.shouldRemind(cleanedBytes: UInt64.max))
    }

    func testSuccessfulEmptyingAvoidsDuplicateWindowAndQuitRemindersUntilMoreCleanup() {
        let domain = "TrashReminderStateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        var state = TrashReminderState(preferences: preferences)

        state.recordTrashEmptied(cleanedBytes: 1_024)

        XCTAssertFalse(state.shouldRemind(cleanedBytes: 0))
        XCTAssertFalse(state.shouldRemind(cleanedBytes: 1_024))
        XCTAssertTrue(state.shouldRemind(cleanedBytes: 1_025))
        XCTAssertTrue(TrashReminderState(preferences: preferences).shouldRemind(cleanedBytes: 1_024))
    }

    func testSuppressionPersistsWhenPreferencesAreReopened() {
        let domain = "TrashReminderStateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        let state = TrashReminderState(preferences: preferences)

        state.setRemindersSuppressed(true)

        let reopened = TrashReminderState(preferences: UserDefaults(suiteName: domain)!)
        XCTAssertFalse(state.shouldRemind(cleanedBytes: 2_048))
        XCTAssertFalse(reopened.shouldRemind(cleanedBytes: 1))
        XCTAssertFalse(reopened.shouldRemind(cleanedBytes: UInt64.max))
    }

    func testEmptyingAcknowledgesOnlyTheCapturedCleanupAndAllowsNewCleanupReminder() {
        let domain = "TrashReminderStateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        var state = TrashReminderState(preferences: preferences)

        state.recordTrashEmptied(cleanedBytes: 1_024)

        XCTAssertFalse(state.shouldRemind(cleanedBytes: 1_024))
        XCTAssertTrue(state.shouldRemind(cleanedBytes: 1_025))
        state.recordTrashEmptied(cleanedBytes: 1)
        XCTAssertFalse(state.shouldRemind(cleanedBytes: 1_024))
        XCTAssertNil(preferences.object(forKey: "cleanup.suppressTrashReminder"))
    }

    func testEmptyingKeepsTheExistingPersistentSuppressionPreference() {
        let domain = "TrashReminderStateTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        var state = TrashReminderState(preferences: preferences)
        state.setRemindersSuppressed(true)

        state.recordTrashEmptied(cleanedBytes: 2_048)

        XCTAssertTrue(preferences.bool(forKey: "cleanup.suppressTrashReminder"))
        XCTAssertFalse(state.shouldRemind(cleanedBytes: UInt64.max))
        XCTAssertFalse(TrashReminderState(preferences: preferences).shouldRemind(cleanedBytes: 1))
    }
}
