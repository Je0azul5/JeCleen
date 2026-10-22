import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(red: 0.08, green: 0.11, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.03, y: p * 0.03, width: p * 0.94, height: p * 0.94), xRadius: p * 0.22, yRadius: p * 0.22).fill()
        let leaf = NSBezierPath()
        leaf.move(to: NSPoint(x: p * 0.29, y: p * 0.28))
        leaf.curve(to: NSPoint(x: p * 0.76, y: p * 0.76), controlPoint1: NSPoint(x: p * 0.12, y: p * 0.70), controlPoint2: NSPoint(x: p * 0.60, y: p * 0.66))
        leaf.curve(to: NSPoint(x: p * 0.29, y: p * 0.28), controlPoint1: NSPoint(x: p * 0.82, y: p * 0.32), controlPoint2: NSPoint(x: p * 0.45, y: p * 0.20))
        NSColor(red: 0.73, green: 0.94, blue: 0.43, alpha: 1).setFill()
        leaf.fill()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: p * 0.25, y: p * 0.22))
        stem.curve(to: NSPoint(x: p * 0.62, y: p * 0.60), controlPoint1: NSPoint(x: p * 0.36, y: p * 0.43), controlPoint2: NSPoint(x: p * 0.42, y: p * 0.43))
        stem.lineWidth = p * 0.025
        stem.lineCapStyle = .round
        NSColor(red: 0.08, green: 0.11, blue: 0.10, alpha: 1).setStroke()
        stem.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
