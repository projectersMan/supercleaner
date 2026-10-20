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
        case .all: L10n.text("全部")
        case .recommended: L10n.text("低风险")
        case .deepClean: L10n.text("可重建")
        case .retain: L10n.text("默认保留")
        case .protected: L10n.text("始终保护")
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
