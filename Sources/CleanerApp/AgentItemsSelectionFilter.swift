import CleanerCore
import Foundation

enum AgentItemsSelectionFilter: String, CaseIterable {
    case all
    case selected

    var displayTitle: String {
        switch self {
        case .all: L10n.text("全部")
        case .selected: L10n.text("已选中")
        }
    }
}
