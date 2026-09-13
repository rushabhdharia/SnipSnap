import AppKit

/// Borderless floating panel that hosts the history UI.
///
/// A plain borderless `NSPanel` refuses key status, which would break the
/// search field and arrow-key navigation — hence the `canBecomeKey` override.
final class SnipSnapPanel: NSPanel {

    /// Invoked when the panel loses key status (click-away dismiss).
    var onResignKey: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        isMovable = true
        minSize = NSSize(width: 320, height: 240)
        hidesOnDeactivate = false
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func cancelOperation(_ sender: Any?) {
        // Ensures the Esc key always reaches the dismiss path even if no
        // SwiftUI responder consumed it.
        onResignKey?()
    }
}
