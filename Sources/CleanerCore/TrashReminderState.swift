import Foundation

public struct TrashReminderState {
    private static let suppressionPreferenceKey = "cleanup.suppressTrashReminder"
    private let preferences: UserDefaults
    private var acknowledgedBytes: UInt64 = 0

    public init(preferences: UserDefaults) {
        self.preferences = preferences
    }

    public func shouldRemind(cleanedBytes: UInt64) -> Bool {
        cleanedBytes > acknowledgedBytes
            && !preferences.bool(forKey: Self.suppressionPreferenceKey)
    }

    public mutating func acknowledge(cleanedBytes: UInt64, suppressReminders: Bool) {
        acknowledgedBytes = max(acknowledgedBytes, cleanedBytes)
        preferences.set(suppressReminders, forKey: Self.suppressionPreferenceKey)
    }
}
