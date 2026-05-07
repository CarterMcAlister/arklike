import AppKit
import SwiftUI

struct MenuBarIcon {
    static func arkImage() -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.labelColor.setStroke()
        NSColor.labelColor.setFill()

        let stroke = NSBezierPath()
        stroke.lineWidth = 1.6
        stroke.lineCapStyle = .round
        stroke.lineJoinStyle = .round

        // Hull: broad curved boat bottom.
        stroke.move(to: NSPoint(x: 3, y: 8))
        stroke.curve(to: NSPoint(x: 19, y: 8), controlPoint1: NSPoint(x: 6, y: 3), controlPoint2: NSPoint(x: 16, y: 3))
        stroke.line(to: NSPoint(x: 16.5, y: 5.2))
        stroke.line(to: NSPoint(x: 5.5, y: 5.2))
        stroke.close()
        stroke.stroke()

        // Cabin / house on top.
        let cabin = NSBezierPath()
        cabin.lineWidth = 1.5
        cabin.lineCapStyle = .round
        cabin.lineJoinStyle = .round
        cabin.move(to: NSPoint(x: 7, y: 8))
        cabin.line(to: NSPoint(x: 7, y: 12))
        cabin.line(to: NSPoint(x: 11, y: 15))
        cabin.line(to: NSPoint(x: 15, y: 12))
        cabin.line(to: NSPoint(x: 15, y: 8))
        cabin.stroke()

        // Roof line.
        let roof = NSBezierPath()
        roof.lineWidth = 1.5
        roof.lineCapStyle = .round
        roof.move(to: NSPoint(x: 6.2, y: 12))
        roof.line(to: NSPoint(x: 11, y: 15.8))
        roof.line(to: NSPoint(x: 15.8, y: 12))
        roof.stroke()

        // Small window.
        let window = NSBezierPath(roundedRect: NSRect(x: 10, y: 9.2, width: 2.2, height: 2.2), xRadius: 0.4, yRadius: 0.4)
        window.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

#if DEBUG
#Preview("Menu Bar Icon") {
    Image(nsImage: MenuBarIcon.arkImage())
        .resizable()
        .aspectRatio(contentMode: .fit)
        .foregroundStyle(.primary)
        .frame(width: 88, height: 72)
        .padding(24)
}
#endif
