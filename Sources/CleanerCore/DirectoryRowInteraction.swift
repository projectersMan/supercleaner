import Foundation

public enum DirectoryRowClickAction: Equatable, Sendable {
    case select
    case selectAndToggleExpansion
}

public enum DirectoryRowInteraction {
    public static func action(
        clickCount: Int,
        kind: FileIdentity.Kind,
        hasChildren: Bool
    ) -> DirectoryRowClickAction {
        guard clickCount >= 1, kind == .directory, hasChildren else {
            return .select
        }
        return .selectAndToggleExpansion
    }
}
