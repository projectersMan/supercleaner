import Foundation

public struct TrashReminderState {
    public static let suppressionPreferenceKey = "cleanup.suppressTrashReminder"
    private let preferences: UserDefaults
    private var acknowledgedBytes: UInt64 = 0

    public init(preferences: UserDefaults) {
        self.preferences = preferences
    }

    public func shouldRemind(cleanedBytes: UInt64) -> Bool {
        cleanedBytes > acknowledgedBytes
            && !preferences.bool(forKey: Self.suppressionPreferenceKey)
    }

    public func setRemindersSuppressed(_ suppressed: Bool) {
        preferences.set(suppressed, forKey: Self.suppressionPreferenceKey)
    }

    public mutating func recordTrashEmptied(cleanedBytes: UInt64) {
        acknowledgedBytes = max(acknowledgedBytes, cleanedBytes)
    }
}
