// Renders AppIcon.icns: swift scripts/make_icon.swift && iconutil -c icns AppIcon.iconset
import AppKit

let sizes: [(String, Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
    ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024),
]
let dir = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.20, alpha: 1),
                        NSColor(calibratedRed: 0.55, green: 0.20, blue: 0.85, alpha: 1)])!.draw(in: path, angle: -60)
    let config = NSImage.SymbolConfiguration(pointSize: rect.width * 0.5, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let sz = sym.size
        sym.draw(in: NSRect(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in sizes {
    try! render(px).write(to: dir.appendingPathComponent("icon_\(name).png"))
}
print("ok")
