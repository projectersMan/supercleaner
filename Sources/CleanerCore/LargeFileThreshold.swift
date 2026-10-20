import Foundation

public enum LargeFileThreshold: UInt64, Codable, CaseIterable, Hashable, Sendable {
    case mb10 = 10_000_000
    case mb50 = 50_000_000
    case mb100 = 100_000_000
    case mb500 = 500_000_000
    case gb1 = 1_000_000_000

    public init(storedBytes: UInt64?) {
        self = storedBytes.flatMap(Self.init(rawValue:)) ?? .mb100
    }

    public var bytes: UInt64 { rawValue }

    public var displayTitle: String {
        switch self {
        case .mb10: "10 MB"
        case .mb50: "50 MB"
        case .mb100: L10n.text("100 MB（推荐）")
        case .mb500: "500 MB"
        case .gb1: "1 GB"
        }
    }

    public var shortTitle: String {
        switch self {
        case .mb10: "10 MB"
        case .mb50: "50 MB"
        case .mb100: "100 MB"
        case .mb500: "500 MB"
        case .gb1: "1 GB"
        }
    }
}
