import AppKit
import CleanerCore
import SwiftUI

/// Keep segment geometry independent of the selected label's intrinsic width.
struct ApplicationScopePicker: View {
    @Binding var selection: ApplicationListScope

    var body: some View {
        let scopes = ApplicationListScope.allCases
        return ScopePicker(labels: scopes.map(\.displayTitle), selection: Binding(
            get: { scopes.firstIndex(of: selection) ?? 0 },
            set: { selection = scopes[$0] }
        ))
    }
}

struct ScopePicker: NSViewRepresentable {
    let labels: [String]
    @Binding var selection: Int

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectScope(_:))
        )
        control.segmentStyle = .rounded
        control.segmentDistribution = .fillEqually
        control.controlSize = .small
        control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        control.setAccessibilityLabel(L10n.text("范围"))
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        for (index, label) in labels.enumerated() {
            control.setLabel(label, forSegment: index)
        }
        control.selectedSegment = selection
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<Int>

        init(selection: Binding<Int>) { self.selection = selection }

        @objc func selectScope(_ sender: NSSegmentedControl) {
            guard (0..<sender.segmentCount).contains(sender.selectedSegment) else { return }
            selection.wrappedValue = sender.selectedSegment
        }
    }
}
