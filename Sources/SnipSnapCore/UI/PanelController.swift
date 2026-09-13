import AppKit
import SwiftUI

/// Owns the floating panel: builds it lazily, positions it near the cursor,
/// remembers which app to return focus to, and tears it down on dismiss.
@MainActor
final class PanelController {

    private let store: HistoryStore
    private let paster: Paster

    private var panel: SnipSnapPanel?
    private(set) var previousApp: NSRunningApplication?

    private let defaultPanelSize = NSSize(width: 380, height: 480)
    private static let widthKey = "panelWidth"
    private static let heightKey = "panelHeight"

    init(store: HistoryStore, paster: Paster) {
        self.store = store
        self.paster = paster
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        // Capture the outgoing app *before* we steal focus.
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        positionNearCursor(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        if let panel {
            let size = panel.frame.size
            UserDefaults.standard.set(Double(size.width), forKey: Self.widthKey)
            UserDefaults.standard.set(Double(size.height), forKey: Self.heightKey)
        }
        panel?.orderOut(nil)
    }

    /// The size to open at: the last size the user left it at, or the default.
    private var storedPanelSize: NSSize {
        let defaults = UserDefaults.standard
        let w = defaults.double(forKey: Self.widthKey)
        let h = defaults.double(forKey: Self.heightKey)
        guard w > 0, h > 0 else { return defaultPanelSize }
        return NSSize(width: w, height: h)
    }

    // MARK: - Building

    private func makePanel() -> SnipSnapPanel {
        let size = storedPanelSize
        let panel = SnipSnapPanel(
            contentRect: NSRect(origin: .zero, size: size)
        )
        panel.onResignKey = { [weak self] in self?.hide() }

        let root = HistoryView(
            store: store,
            onPaste: { [weak self] item in
                guard let self else { return }
                self.hide()
                self.paster.paste(item, into: self.previousApp)
            },
            onDismiss: { [weak self] in self?.hide() }
        )

        let hosting = NSHostingView(rootView: root)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let effect = NSHostingView(rootView: VisualEffectBackground())
        effect.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(effect)
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effect.topAnchor.constraint(equalTo: container.topAnchor),
            effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        panel.contentView = container
        return panel
    }

    private func positionNearCursor(_ panel: SnipSnapPanel) {
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }

        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)

        if origin.x + size.width > visible.maxX {
            origin.x = visible.maxX - size.width - 8
        }
        origin.x = max(origin.x, visible.minX + 8)

        if origin.y < visible.minY + 8 {
            origin.y = visible.minY + 8
        }
        if origin.y + size.height > visible.maxY {
            origin.y = visible.maxY - size.height - 8
        }

        panel.setFrameOrigin(origin)
    }
}
