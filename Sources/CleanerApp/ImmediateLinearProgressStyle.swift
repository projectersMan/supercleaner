import SwiftUI

/// The native macOS linear indicator animates behind rapid count updates, even
/// after its accessibility value reaches 100%. Draw the current fraction directly
/// so the operation's count and its visible fill always describe the same state.
struct ImmediateLinearProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(1, max(0, configuration.fractionCompleted ?? 0))
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(Color.accentColor)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 8)
        .transaction { $0.animation = nil }
    }
}
