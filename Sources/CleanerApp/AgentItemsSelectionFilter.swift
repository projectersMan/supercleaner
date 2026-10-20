import Foundation

enum AgentItemsSelectionFilter: String, CaseIterable {
    case all
    case selected

    var displayTitle: String {
        switch self {
        case .all: "全部"
        case .selected: "已选中"
        }
    }
}
