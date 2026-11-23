import AppKit
import SwiftUI

/// Native search editing supplies the inline clear button and keeps the field
/// editor focused when clearing. Both typing and the cancel action update filters.
struct ReviewSearchField: NSViewRepresentable {
    @Binding var query: String
    let prompt: String
    let isCompact: Bool

    func makeCoordinator() -> Coordinator { Coordinator(query: $query) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.target = context.coordinator
        field.action = #selector(Coordinator.queryChanged(_:))
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.recentsAutosaveName = nil
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setAccessibilityIdentifier("review-toolbar-search")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.query = $query
        field.placeholderString = prompt
        field.setAccessibilityLabel(prompt)
        field.controlSize = isCompact ? .small : .regular
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        // Progress updates must not replace an in-progress input-method composition.
        if field.stringValue != query, (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
            field.stringValue = query
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSearchField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: nsView.intrinsicContentSize.height)
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var query: Binding<String>
        init(query: Binding<String>) { self.query = query }

        @objc func queryChanged(_ field: NSSearchField) { updateQuery(field) }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            updateQuery(field)
        }
        private func updateQuery(_ field: NSSearchField) {
            guard (field.currentEditor() as? NSTextView)?.hasMarkedText() != true,
                  query.wrappedValue != field.stringValue else { return }
            query.wrappedValue = field.stringValue
        }
    }
}
