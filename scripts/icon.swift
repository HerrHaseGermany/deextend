import AppKit

let output = CommandLine.arguments[1] + "/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        let background = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 206, yRadius: 206)
        NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.57, blue: 0.59, alpha: 1), ending: NSColor(calibratedRed: 0.02, green: 0.20, blue: 0.26, alpha: 1))!.draw(in: background, angle: -90)
        NSColor.white.setStroke()
        let display = NSBezierPath(roundedRect: NSRect(x: 227, y: 360, width: 570, height: 380), xRadius: 36, yRadius: 36)
        display.lineWidth = 35
        display.stroke()
        let stand = NSBezierPath()
        stand.move(to: NSPoint(x: 512, y: 360)); stand.line(to: NSPoint(x: 512, y: 267))
        stand.move(to: NSPoint(x: 402, y: 267)); stand.line(to: NSPoint(x: 622, y: 267))
        stand.lineWidth = 35; stand.lineCapStyle = .round; stand.stroke()
        NSColor(calibratedRed: 0.04, green: 0.32, blue: 0.37, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 618, y: 301, width: 213, height: 213)).fill()
        NSColor.white.setStroke()
        let pause = NSBezierPath()
        pause.move(to: NSPoint(x: 694, y: 362)); pause.line(to: NSPoint(x: 694, y: 452))
        pause.move(to: NSPoint(x: 753, y: 362)); pause.line(to: NSPoint(x: 753, y: 452))
        pause.lineWidth = 24; pause.lineCapStyle = .round; pause.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size)\(suffix).png"))
    }
}
