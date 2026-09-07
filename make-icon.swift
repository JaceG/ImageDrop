// Generates AppIcon.icns for ImageDrop: a blue→violet rounded square with the same
// "photo.on.rectangle.angled" symbol used in the menu bar. Run via ./make-icon.sh.
import Cocoa

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // macOS icon grid: artwork sits inside ~80% of the canvas.
    let inset = s * 0.10
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.height * 0.225)

    let shadow = NSShadow()
    shadow.shadowBlurRadius = s * 0.02; shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSShadow().set()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.55, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.45, green: 0.30, blue: 0.95, alpha: 1)
    ])!
    gradient.draw(in: shape, angle: -60)

    // Soft highlight across the top for depth.
    NSGraphicsContext.current?.saveGraphicsState()
    shape.addClip()
    let hl = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    hl.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: 90)
    NSGraphicsContext.current?.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            NSColor.white.set(); r.fill(using: .sourceAtop)
            return true
        }
        let sz = tinted.size
        let origin = NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2)
        tinted.draw(in: NSRect(origin: origin, size: sz))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(px).representation(using: .png, properties: [:])!
        try! data.write(to: out.appendingPathComponent(name))
    }
}
print("wrote iconset to \(out.path)")
