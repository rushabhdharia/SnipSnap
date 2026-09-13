import AppKit
import SnipSnapCore

// SwiftPM executable targets use `main.swift` as the entry point; `@main`
// alongside it would be a compile error. Top-level code here isn't
// automatically main-actor isolated under this toolchain, so assert it — the
// process only ever has the one thread at this point.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
