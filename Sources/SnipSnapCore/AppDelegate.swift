import AppKit
import SwiftUI

/// Wires the four subsystems together and owns the menu bar item.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    public override init() { super.init() }


    private let store = HistoryStore()
    private let monitor = SnipSnapMonitor()
    private let hotKey = HotKeyManager()
    private lazy var paster = Paster(store: store, monitor: monitor)
    private lazy var panel = PanelController(store: store, paster: paster)

    private var statusItem: NSStatusItem?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        monitor.onCopy = { [store] content in store.add(content) }
        monitor.start()

        hotKey.onFire = { [weak self] in self?.panel.toggle() }
        hotKey.register()

        setUpStatusItem()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        hotKey.unregister()
        monitor.stop()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "SnipSnap history"
        )

        let menu = NSMenu()

        let show = NSMenuItem(
            title: "Show SnipSnap",
            action: #selector(showPanel),
            keyEquivalent: "v"
        )
        show.keyEquivalentModifierMask = [.command, .control]
        show.target = self
        menu.addItem(show)

        menu.addItem(.separator())

        let clear = NSMenuItem(
            title: "Clear History…",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit SnipSnap",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }


    @objc private func showPanel() {
        panel.show()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This permanently removes every item, including pinned ones."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }
}
