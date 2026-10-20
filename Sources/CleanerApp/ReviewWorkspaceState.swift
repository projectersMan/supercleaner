import CleanerCore

enum ReviewDispositionFilter: String, CaseIterable, Identifiable {
    case all
    case recommended
    case deepClean
    case retain
    case protected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .recommended: "低风险"
        case .deepClean: "可重建"
        case .retain: "默认保留"
        case .protected: "始终保护"
        }
    }

    var dispositions: Set<CleanupDisposition> {
        switch self {
        case .all: Set(CleanupDisposition.allCases)
        case .recommended: [.recommended]
        case .deepClean: [.deepClean]
        case .retain: [.retain]
        case .protected: [.protected]
        }
    }
}
