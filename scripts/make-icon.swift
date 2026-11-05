import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let box = NSRect(x: p * 0.055, y: p * 0.055, width: p * 0.89, height: p * 0.89)
        let rounded = NSBezierPath(roundedRect: box, xRadius: p * 0.2, yRadius: p * 0.2)
        NSGradient(starting: NSColor(red: 0.1, green: 0.36, blue: 0.83, alpha: 1),
                   ending: NSColor(red: 0.09, green: 0.13, blue: 0.35, alpha: 1))!.draw(in: rounded, angle: -60)
        let points = [NSPoint(x: p * 0.3, y: p * 0.34), NSPoint(x: p * 0.7, y: p * 0.34), NSPoint(x: p * 0.5, y: p * 0.71)]
        let path = NSBezierPath()
        path.move(to: points[0]); path.line(to: points[2]); path.line(to: points[1]); path.line(to: points[0])
        path.lineWidth = p * 0.045; path.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(0.7).setStroke(); path.stroke()
        for point in points {
            let circle = NSBezierPath(ovalIn: NSRect(x: point.x - p * 0.09, y: point.y - p * 0.09, width: p * 0.18, height: p * 0.18))
            NSColor.white.setFill(); circle.fill()
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        let file = URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: file)
    }
}
