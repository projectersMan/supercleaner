import Foundation

enum AgentOverlapThresholdOption: Int, CaseIterable {
    case eighty = 80, eightyFive = 85, ninety = 90, ninetyFive = 95, hundred = 100

    var fraction: Double { Double(rawValue) / 100 }

    static func nearest(to fraction: Double) -> Self {
        guard fraction.isFinite else { return .eightyFive }
        return allCases.min {
            let left = abs($0.fraction - fraction), right = abs($1.fraction - fraction)
            return left == right ? $0.rawValue > $1.rawValue : left < right
        }!
    }
}
