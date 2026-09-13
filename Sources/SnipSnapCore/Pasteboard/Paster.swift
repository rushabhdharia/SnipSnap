import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// Puts a history item back on the system pasteboard and, when permitted,
/// synthesises ⌘V into whatever app was frontmost before the panel opened.
///
/// If Accessibility permission is missing, everything short of the synthetic
/// keystroke still happens: the item is on the clipboard and the user can
/// press ⌘V themselves. The feature degrades; it never dead-ends.
final class Paster {

    private let store: HistoryStore
    private let monitor: SnipSnapMonitor
    private var hasPromptedForAccessibility = false

    init(store: HistoryStore, monitor: SnipSnapMonitor) {
        self.store = store
        self.monitor = monitor
    }

    /// - Parameters:
    ///   - item: the history entry to paste.
    ///   - into: the app that was frontmost before the panel appeared.
    func paste(_ item: ClipItem, into previousApp: NSRunningApplication?) {
        writeToPasteboard(item)

        previousApp?.activate()

        guard AXIsProcessTrusted() else {
            promptForAccessibilityOnce()
            return
        }

        // Let the target app finish coming forward before the keystroke lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.postCommandV()
        }
    }

    /// Copy only — no synthetic keystroke.
    func copyToPasteboard(_ item: ClipItem) {
        writeToPasteboard(item)
    }

    // MARK: - Pasteboard

    private func writeToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            if let text = store.resolveText(for: item) {
                pb.setString(text, forType: .string)
            }
        case .image:
            if let data = store.fullImageData(for: item) {
                pb.setData(data, forType: .png)
            }
        }
        // The monitor will see this change next tick; tell it that it's ours.
        monitor.ignoreNextChange(count: pb.changeCount)
    }

    // MARK: - Synthetic keystroke

    private static func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        let tap: CGEventTapLocation = .cgAnnotatedSessionEventTap
        down.post(tap: tap)
        up.post(tap: tap)
    }

    // MARK: - Permission

    private func promptForAccessibilityOnce() {
        guard !hasPromptedForAccessibility else { return }
        hasPromptedForAccessibility = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
