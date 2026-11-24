import SwiftUI

struct ReviewToolbarMetrics {
    let isCompact: Bool
    init(width: CGFloat) { isCompact = width < 1100 }
    var spacing: CGFloat { isCompact ? 3 : 12 }
    var labelSpacing: CGFloat { isCompact ? 4 : 8 }
    var leadingInset: CGFloat { isCompact ? 12 : 18 }
    var trailingInset: CGFloat { isCompact ? 12 : 20 }
    var searchWidth: CGFloat { isCompact ? 170 : 260 }
    var selectAllWidth: CGFloat { isCompact ? 76 : 92 }
    var segmentWidth: CGFloat { isCompact ? 88 : 105 }
    var dropdownWidth: CGFloat { isCompact ? 120 : 140 }
    var applicationScopeWidth: CGFloat { scopeWidth(count: 4) }
    var largeFileScopeWidth: CGFloat { 2 * max(segmentWidth, 140) }
    var agentTypeWidth: CGFloat { scopeWidth(count: 2) }
    func scopeWidth(count: Int) -> CGFloat { CGFloat(count) * segmentWidth }

}

/// The compact metrics fit every control inside the existing 760 pt minimum detail column.
struct ReviewToolbar<Controls: View>: View {
    @Binding var query: String
    let prompt: String
    @ViewBuilder var controls: (ReviewToolbarMetrics) -> Controls

    var body: some View {
        GeometryReader { geometry in
            let metrics = ReviewToolbarMetrics(width: geometry.size.width)
            HStack(spacing: metrics.spacing) {
                HStack(spacing: metrics.spacing) { controls(metrics) }
                    .fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 0)
                ReviewSearchField(query: $query, prompt: prompt, isCompact: metrics.isCompact)
                    .frame(width: metrics.searchWidth)
                    .accessibilityIdentifier("review-toolbar-search")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .font(.caption)
            .controlSize(metrics.isCompact ? .small : .regular)
            .padding(.leading, metrics.leadingInset)
            .padding(.trailing, metrics.trailingInset)
        }
        .frame(height: 44)
        .lineLimit(1)
        .background(.bar)
        .accessibilityIdentifier("review-toolbar")
    }
}
