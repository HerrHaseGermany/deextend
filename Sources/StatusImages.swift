import AppKit

/// Template artwork follows the menu bar’s light and dark appearance.
enum StatusImages {
    static let pausedDisplay: NSImage = {
        let image = NSImage(size: NSSize(width: 23, height: 18), flipped: false) { _ in
            NSImage(systemSymbolName: "display", accessibilityDescription: nil)?
                .draw(in: NSRect(x: 0, y: 2, width: 21, height: 16))
            NSColor.black.setFill()
            for x in [7.8, 11.5] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 8.5, width: 1.8, height: 5.8),
                             xRadius: 0.35, yRadius: 0.35).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = L.text("display.paused")
        return image
    }()
}
