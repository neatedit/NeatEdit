// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // macOS icon grid: 824pt body centred on a 1024pt canvas.
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.27, alpha: 1),
                        NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1)])!
        .draw(in: body, angle: -90)

    // Faint "text lines" in the lower part.
    NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
    let widths: [CGFloat] = [520, 380, 460]
    for (i, w) in widths.enumerated() {
        let y = (330 - CGFloat(i) * 78) * s
        NSBezierPath(roundedRect: NSRect(x: 196 * s, y: y, width: w * s, height: 30 * s),
                     xRadius: 15 * s, yRadius: 15 * s).fill()
    }

    // "Aa" in monospaced type with an orange caret.
    let font = NSFont.monospacedSystemFont(ofSize: 330 * s, weight: .semibold)
    let text = NSAttributedString(string: "Aa", attributes: [
        .font: font, .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1)])
    let size = text.size()
    let origin = NSPoint(x: 196 * s - 14 * s, y: 430 * s)
    text.draw(at: origin)
    NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.15, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: origin.x + size.width + 22 * s, y: 455 * s, width: 34 * s, height: 300 * s),
                 xRadius: 10 * s, yRadius: 10 * s).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote \(output.path)" : "iconutil failed")
// Keep a preview next to the iconset for a quick look.
print("preview: \(iconset.appendingPathComponent("icon_512x512@2x.png").path)")
