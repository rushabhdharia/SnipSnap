#!/bin/bash
#
# Renders a minimal clipboard app icon to the .icns path given as $1.
# Uses an offscreen Swift/AppKit draw — no assets, no network.

set -euo pipefail
OUT="${1:?usage: make-icon.sh <path/to/AppIcon.icns>}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

RENDER="$WORK/render.swift"
cat > "$RENDER" <<'SWIFT'
import AppKit

func drawIcon(size: Int, to url: URL) {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded app tile with a vertical accent gradient.
    let inset = s * 0.06
    let tile = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: s * 0.22, yRadius: s * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.36, blue: 0.92, alpha: 1),
    ])
    gradient?.draw(in: tilePath, angle: -90)

    // Clipboard body (the drawn icon shape — a literal clipboard).
    let bw = s * 0.44, bh = s * 0.52
    let body = NSRect(x: (s - bw) / 2, y: (s - bh) / 2 - s * 0.02, width: bw, height: bh)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: body, xRadius: s * 0.05, yRadius: s * 0.05).fill()

    // Clip at the top.
    let cw = s * 0.20, ch = s * 0.10
    let clip = NSRect(x: (s - cw) / 2, y: body.maxY - ch * 0.55, width: cw, height: ch)
    NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
    NSBezierPath(roundedRect: clip, xRadius: s * 0.03, yRadius: s * 0.03).fill()

    // A couple of text lines.
    NSColor(calibratedRed: 0.30, green: 0.55, blue: 1.00, alpha: 1).setFill()
    let lx = body.minX + bw * 0.16
    let lw = bw * 0.68
    for i in 0..<3 {
        let ly = body.maxY - ch - s * 0.10 - CGFloat(i) * s * 0.10
        NSBezierPath(
            roundedRect: NSRect(x: lx, y: ly, width: i == 2 ? lw * 0.6 : lw, height: s * 0.035),
            xRadius: s * 0.02, yRadius: s * 0.02
        ).fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
    }
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in variants {
    drawIcon(size: px, to: iconset.appendingPathComponent("\(name).png"))
}
SWIFT

swift "$RENDER" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$OUT"
echo "    wrote $OUT"
