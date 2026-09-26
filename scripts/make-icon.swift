// Draws the app icon (a mini Sankey) and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let bg = NSBezierPath(roundedRect: NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s),
                          xRadius: 185 * s, yRadius: 185 * s)
    NSColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1).setFill()
    bg.fill()

    func ribbon(_ x0: CGFloat, _ y0: CGFloat, _ y0b: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ y1b: CGFloat, _ c: NSColor) {
        let p = NSBezierPath(); let xm = (x0 + x1) / 2
        p.move(to: NSPoint(x: x0 * s, y: y0 * s))
        p.curve(to: NSPoint(x: x1 * s, y: y1 * s), controlPoint1: NSPoint(x: xm * s, y: y0 * s), controlPoint2: NSPoint(x: xm * s, y: y1 * s))
        p.line(to: NSPoint(x: x1 * s, y: y1b * s))
        p.curve(to: NSPoint(x: x0 * s, y: y0b * s), controlPoint1: NSPoint(x: xm * s, y: y1b * s), controlPoint2: NSPoint(x: xm * s, y: y0b * s))
        c.withAlphaComponent(0.75).setFill(); p.fill()
    }
    let blue = NSColor(red: 0.30, green: 0.56, blue: 0.98, alpha: 1)
    let orange = NSColor(red: 0.96, green: 0.50, blue: 0.24, alpha: 1)
    let purple = NSColor(red: 0.66, green: 0.44, blue: 0.92, alpha: 1)
    let teal = NSColor(red: 0.20, green: 0.75, blue: 0.62, alpha: 1)
    // Source bar on the left, fanning out to four bars on the right.
    ribbon(250, 780, 600, 740, 820, 640, blue)
    ribbon(250, 600, 460, 740, 580, 440, orange)
    ribbon(250, 460, 360, 740, 400, 300, purple)
    ribbon(250, 360, 240, 740, 260, 140 + 40, teal)
    NSColor(red: 0.35, green: 0.85, blue: 0.50, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 215 * s, y: 240 * s, width: 40 * s, height: 540 * s), xRadius: 8 * s, yRadius: 8 * s).fill()
    for (c, y0, y1) in [(blue, 640.0, 820.0), (orange, 440.0, 580.0), (purple, 300.0, 400.0), (teal, 180.0, 260.0)] {
        c.setFill()
        NSBezierPath(roundedRect: NSRect(x: 735 * s, y: y0 * s, width: 40 * s, height: (y1 - y0) * s), xRadius: 8 * s, yRadius: 8 * s).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! draw(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run(); task.waitUntilExit()
print("Wrote Resources/AppIcon.icns")
