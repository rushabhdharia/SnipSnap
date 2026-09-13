import SwiftUI
import AppKit

/// A transparent view that lets its owning window be dragged from this
/// region. `NSHostingView` doesn't opt into window dragging on its own, so a
/// drag handle placed over SwiftUI content needs this underneath it.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}
