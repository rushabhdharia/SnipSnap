import AppKit
import SwiftUI
import ServiceManagement

/// Wires the four subsystems together and owns the menu bar item.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    public override init() { super.init() }


    private let store = HistoryStore()
    private let monitor = SnipSnapMonitor()
    private let hotKey = HotKeyManager()
    private lazy var paster = Paster(store: store, monitor: monitor)
    private lazy var panel = PanelController(store: store, paster: paster)

    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?

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
        menu.delegate = self

        let show = NSMenuItem(
            title: "Show SnipSnap",
            action: #selector(showPanel),
            keyEquivalent: "v"
        )
        show.keyEquivalentModifierMask = [.command, .control]
        show.target = self
        menu.addItem(show)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        menu.addItem(launchAtLogin)
        launchAtLoginItem = launchAtLogin

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


    // MARK: - Launch at Login

    /// Reflects the real `SMAppService` status rather than a cached flag, so
    /// this stays correct even if the user disables it from System
    /// Settings ▸ General ▸ Login Items instead of this menu.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        launchAtLoginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("SnipSnap: failed to toggle launch-at-login: \(error)")
        }
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
