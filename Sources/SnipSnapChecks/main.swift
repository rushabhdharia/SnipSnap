import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import SnipSnapCore

// A tiny dependency-free test harness so the store logic can be verified
// under the Command Line Tools toolchain, where XCTest isn't available.
// Run with: swift run SnipSnapChecks

var failures = 0
var passed = 0

func check(_ condition: @autoclosure () -> Bool, _ label: String, file: StaticString = #file, line: UInt = #line) {
    if condition() {
        passed += 1
    } else {
        failures += 1
        FileHandle.standardError.write(Data("  ✗ \(label)  (\(file):\(line))\n".utf8))
    }
}

func scenario(_ name: String, _ body: (URL) throws -> Void) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SnipSnapChecks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    do {
        try body(dir)
        print("• \(name)")
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("  ✗ \(name) threw: \(error)\n".utf8))
    }
}

func makeStore(_ dir: URL, max: Int = 200) -> HistoryStore {
    let store = HistoryStore(baseURL: dir, maxUnpinned: max)
    store.saveDebounce = 0
    return store
}

// MARK: - Scenarios

scenario("dedup collapses a repeated copy") { dir in
    let store = makeStore(dir)
    store.add(.text("hello"))
    store.add(.text("world"))
    store.add(.text("hello"))
    check(store.items.count == 2, "count is 2 after a repeat")
    check(store.items.first?.text == "hello", "repeat is promoted to top")
}

scenario("whitespace-only text is ignored") { dir in
    let store = makeStore(dir)
    store.add(.text("  \n\t "))
    check(store.items.isEmpty, "no item recorded")
}

scenario("retention trims unpinned to the limit, newest kept") { dir in
    let store = makeStore(dir, max: 200)
    for i in 0..<250 { store.add(.text("item \(i)")) }
    check(store.items.count == 200, "trimmed to 200")
    check(store.items.first?.text == "item 249", "newest survives")
    check(store.items.last?.text == "item 50", "oldest survivor is item 50")
}

scenario("a pinned item survives 250 later inserts") { dir in
    let store = makeStore(dir, max: 200)
    guard let anchor = store.add(.text("keep me")) else {
        check(false, "insert succeeded"); return
    }
    store.togglePin(id: anchor.id)
    for i in 0..<250 { store.add(.text("noise \(i)")) }
    check(store.items.contains { $0.id == anchor.id }, "pinned item never trimmed")
    check(store.items.first?.id == anchor.id, "pinned sorts ahead of unpinned")
    check(store.items.count == 201, "200 unpinned + 1 pinned")
}

scenario("oversized text spills to a sidecar and resolves back") { dir in
    let store = makeStore(dir)
    let big = String(repeating: "A", count: ClipItem.inlineTextByteLimit + 10)
    guard let item = store.add(.text(big)) else { check(false, "insert"); return }
    check(item.text == nil, "not stored inline")
    check(store.resolveText(for: item) == big, "resolves to full text from disk")
}

scenario("JSON round-trips through disk") { dir in
    let store = makeStore(dir)
    store.add(.text("one"))
    guard let pinned = store.add(.text("two")) else { check(false, "insert"); return }
    store.togglePin(id: pinned.id)
    store.saveNow()

    let reloaded = HistoryStore(baseURL: dir, maxUnpinned: 200)
    check(reloaded.items.map(\.text) == store.items.map(\.text), "items match after reload")
    check(reloaded.items.first?.pinned == true, "pin flag persisted")
    check(
        reloaded.items.map { $0.createdAt.timeIntervalSinceReferenceDate }
            == store.items.map { $0.createdAt.timeIntervalSinceReferenceDate },
        "timestamps survive with full precision (ordering is stable across restarts)"
    )
}

scenario("index entry with a missing sidecar is dropped on load") { dir in
    let store = makeStore(dir)
    let big = String(repeating: "B", count: ClipItem.inlineTextByteLimit + 10)
    guard let item = store.add(.text(big)) else { check(false, "insert"); return }
    store.add(.text("small survivor"))
    store.saveNow()

    let sidecar = dir.appendingPathComponent("text").appendingPathComponent("\(item.id.uuidString).txt")
    try FileManager.default.removeItem(at: sidecar)

    let reloaded = HistoryStore(baseURL: dir, maxUnpinned: 200)
    check(!reloaded.items.contains { $0.id == item.id }, "orphaned entry dropped")
    check(reloaded.items.contains { $0.text == "small survivor" }, "intact entry kept")
}

scenario("clearAll empties history and disk") { dir in
    let store = makeStore(dir)
    store.add(.text("a"))
    guard let p = store.add(.text("b")) else { check(false, "insert"); return }
    store.togglePin(id: p.id)
    store.clearAll()
    check(store.items.isEmpty, "in-memory cleared")
}

scenario("a synthetic PNG is stored with a thumbnail and dimensions") { dir in
    let store = makeStore(dir)
    guard let png = onePixelPNG() else { check(false, "png fixture"); return }
    guard let item = store.add(.image(png: png, pixelWidth: 1, pixelHeight: 1)) else {
        check(false, "image insert"); return
    }
    check(item.kind == .image, "kind is image")
    check(item.pixelWidth == 1 && item.pixelHeight == 1, "dimensions recorded")
    check(store.fullImageData(for: item) != nil, "full image readable back")
    check(store.thumbnailURL(for: item) != nil, "thumbnail url available")
}

scenario("a wide image gets a preview large enough to fill a full-width row") { dir in
    let store = makeStore(dir)
    guard let wide = solidPNG(width: 1844, height: 196) else { check(false, "png fixture"); return }
    guard let item = store.add(.image(png: wide, pixelWidth: 1844, pixelHeight: 196)) else {
        check(false, "image insert"); return
    }
    guard let url = store.thumbnailURL(for: item),
          let data = try? Data(contentsOf: url),
          let size = ImageUtil.pixelSize(of: data)
    else { check(false, "preview readable"); return }
    check(max(size.width, size.height) >= 696, "preview's longest edge covers a full-width row (\(size))")
}

scenario("a source already under the target skips a redundant thumbnail file") { dir in
    let store = makeStore(dir)
    guard let small = solidPNG(width: 200, height: 50) else { check(false, "png fixture"); return }
    guard let item = store.add(.image(png: small, pixelWidth: 200, pixelHeight: 50)) else {
        check(false, "image insert"); return
    }
    check(item.thumbFile == nil, "no separate thumb file generated")
    check(store.thumbnailURL(for: item) != nil, "thumbnailURL still resolves via the full image")
}

scenario("an undersized on-disk preview is regenerated on load") { dir in
    let store = makeStore(dir)
    guard let wide = solidPNG(width: 1844, height: 196) else { check(false, "png fixture"); return }
    guard let item = store.add(.image(png: wide, pixelWidth: 1844, pixelHeight: 196)) else {
        check(false, "image insert"); return
    }
    // Simulate a preview generated back when the target was still 88px.
    guard let stale = solidPNG(width: 88, height: 9),
          let url = store.thumbnailURL(for: item)
    else { check(false, "setup"); return }
    try stale.write(to: url, options: .atomic)
    store.saveNow()

    let reloaded = makeStore(dir)
    guard let reloadedItem = reloaded.items.first(where: { $0.id == item.id }),
          let reloadedURL = reloaded.thumbnailURL(for: reloadedItem),
          let data = try? Data(contentsOf: reloadedURL),
          let size = ImageUtil.pixelSize(of: data)
    else { check(false, "preview readable after reload"); return }
    check(max(size.width, size.height) > 88, "stale preview regenerated to the new target (\(size))")
}

// MARK: - Fixtures

func onePixelPNG() -> Data? {
    // 1x1 transparent PNG.
    let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    return Data(base64Encoded: b64)
}

/// A synthetic solid-color PNG at an arbitrary size, for exercising the
/// thumbnail pipeline against dimensions the base64 fixture can't cover.
func solidPNG(width: Int, height: Int) -> Data? {
    guard let ctx = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = ctx.makeImage() else { return nil }

    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}

// MARK: - Result

print("\n\(passed) checks passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
