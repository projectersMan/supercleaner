import AppKit
import CleanerCore
import SwiftUI

/// Keep segment geometry independent of the selected label's intrinsic width.
struct ApplicationScopePicker: NSViewRepresentable {
    @Binding var selection: ApplicationListScope

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: ApplicationListScope.allCases.map(\.displayTitle),
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
        for (index, scope) in ApplicationListScope.allCases.enumerated() {
            control.setLabel(scope.displayTitle, forSegment: index)
        }
        control.selectedSegment = ApplicationListScope.allCases.firstIndex(of: selection)!
    }

    @MainActor final class Coordinator: NSObject {
        var selection: Binding<ApplicationListScope>

        init(selection: Binding<ApplicationListScope>) { self.selection = selection }

        @objc func selectScope(_ sender: NSSegmentedControl) {
            guard ApplicationListScope.allCases.indices.contains(sender.selectedSegment) else { return }
            selection.wrappedValue = ApplicationListScope.allCases[sender.selectedSegment]
        }
    }
}
