#!/usr/bin/env swift
import AppKit

// Renders the DMG window background, in the icon's slate and amber.
// Usage: swift scripts/make-dmg-background.swift <scale> <output.png>
// The window is 620x420 points; the icons' centres are 235 points from the top.

let scale = CGFloat(Double(CommandLine.arguments[1]) ?? 1)
let output = CommandLine.arguments[2]
let width: CGFloat = 620, height: CGFloat = 420

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let slate = NSColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1)
let muted = NSColor(red: 0.42, green: 0.45, blue: 0.50, alpha: 1)
let amber = NSColor(red: 1.00, green: 0.65, blue: 0.17, alpha: 1)

// Light, because Finder draws the icons' labels in dark text.
NSGradient(starting: NSColor(red: 0.99, green: 0.98, blue: 0.97, alpha: 1),
           ending: NSColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

func centred(_ text: String, y: CGFloat, _ attributes: [NSAttributedString.Key: Any]) -> NSRect {
    let size = text.size(withAttributes: attributes)
    let origin = NSPoint(x: (width - size.width) / 2, y: y)
    text.draw(at: origin, withAttributes: attributes)
    return NSRect(origin: origin, size: size)
}

// The title with the icon's caret after it.
let title = centred("NeatEdit", y: height - 76, [
    .font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: slate,
])
amber.setFill()
NSBezierPath(roundedRect: NSRect(x: title.maxX + 4, y: title.minY + 6, width: 4, height: title.height - 12),
             xRadius: 2, yRadius: 2).fill()

_ = centred("Drag NeatEdit onto the Applications folder to install", y: height - 106, [
    .font: NSFont.systemFont(ofSize: 14), .foregroundColor: muted,
])

// The arrow between the icons.
let arrowY = height - 235
amber.set()
let shaft = NSBezierPath()
shaft.lineWidth = 5
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 268, y: arrowY))
shaft.line(to: NSPoint(x: 340, y: arrowY))
shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 362, y: arrowY))
head.line(to: NSPoint(x: 340, y: arrowY + 12))
head.line(to: NSPoint(x: 340, y: arrowY - 12))
head.close()
head.fill()

NSGraphicsContext.current = nil
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
