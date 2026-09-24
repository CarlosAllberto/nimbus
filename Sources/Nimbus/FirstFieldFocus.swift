import AppKit
import SwiftUI

/// Gives keyboard focus to the first editable text field of the tool detail
/// pane. Attach with `.background(FirstFieldFocus(trigger:))`; focus is taken
/// once when the anchor enters a window, and again whenever `trigger` changes
/// (opening the tool that is already showing). Only the detail pane is searched,
/// never the sidebar. A tool with no text field takes no focus.
/// `preferredPlaceholder` picks a specific field instead of the first one.
struct FirstFieldFocus: NSViewRepresentable {
    var trigger: Int = 0
    var preferredPlaceholder: String? = nil

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.trigger = trigger
        view.preferredPlaceholder = preferredPlaceholder
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.preferredPlaceholder = preferredPlaceholder
        guard view.trigger != trigger else { return }
        view.trigger = trigger
        view.focusFirstField()
    }

    final class AnchorView: NSView {
        var trigger = 0
        var preferredPlaceholder: String?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            focusFirstField()
        }

        func focusFirstField() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, let pane = self.detailPane() else { return }
                guard let field = Self.firstEditableField(in: pane, preferring: self.preferredPlaceholder) else { return }
                window.makeFirstResponder(field)
            }
        }

        /// The split view's detail column: the ancestor whose parent is the
        /// `NSSplitView`. Nil outside a split view, which then focuses nothing.
        private func detailPane() -> NSView? {
            var view: NSView? = self
            while let current = view, let parent = current.superview {
                if parent is NSSplitView { return current }
                view = parent
            }
            return nil
        }

        private static func firstEditableField(in root: NSView, preferring placeholder: String?) -> NSView? {
            var candidates: [NSView] = []
            collect(in: root, into: &candidates)
            if let placeholder,
               let match = candidates.first(where: { ($0 as? NSTextField)?.placeholderString == placeholder }) {
                return match
            }
            // Visual order: topmost first, then leftmost.
            return candidates.min { lhs, rhs in
                let l = lhs.convert(lhs.bounds, to: nil)
                let r = rhs.convert(rhs.bounds, to: nil)
                if abs(l.maxY - r.maxY) > 1 { return l.maxY > r.maxY }
                return l.minX < r.minX
            }
        }

        private static func collect(in view: NSView, into result: inout [NSView]) {
            guard !view.isHidden else { return }
            if let field = view as? NSTextField, field.isEditable, field.acceptsFirstResponder {
                result.append(field)
            } else if let text = view as? NSTextView, text.isEditable, !text.isFieldEditor {
                result.append(text)
            }
            for sub in view.subviews { collect(in: sub, into: &result) }
        }
    }
}
