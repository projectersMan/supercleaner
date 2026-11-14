import Foundation

@main enum TrashReminderPreferencesCheck {
    static func main() {
        let arguments = CommandLine.arguments
        precondition(arguments.count == 3, "Expected write/read and an isolated preferences domain")
        let preferences = UserDefaults(suiteName: arguments[2])!
        var state = TrashReminderState(preferences: preferences)

        switch arguments[1] {
        case "write":
            preferences.removePersistentDomain(forName: arguments[2])
            precondition(state.shouldRemind(cleanedBytes: 1))
            state.acknowledge(cleanedBytes: 1, suppressReminders: true)
            print("PASS: first process saves suppression")
        case "read":
            precondition(!state.shouldRemind(cleanedBytes: UInt64.max))
            preferences.removePersistentDomain(forName: arguments[2])
            print("PASS: second process honors persisted suppression and removes its test domain")
        default:
            preconditionFailure("Expected write or read")
        }
    }
}
