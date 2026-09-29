// Renders each concept SVG to PNGs and builds a labelled comparison sheet.
// Usage: swift render.swift <current-icon-1024.png> <out-dir>
import AppKit

let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let out = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func bitmap(_ w: Int, _ h: Int, _ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

func over(_ rep: NSBitmapImageRep, _ rect: NSRect) {
    rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
}

let concepts = [("A · Running dial", "concept-a-dial"), ("B · Already playing", "concept-b-play"), ("C · Tomato ring", "concept-c-tomato")]
var icons = [("Current", NSImage(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!)]
for (label, file) in concepts {
    let svg = NSImage(contentsOf: dir.appendingPathComponent("\(file).svg"))!
    for px in [1024, 128, 32, 16] {
        save(bitmap(px, px) { svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px)) }, "\(file)-\(px).png")
    }
    // Downscale from the 1024 raster, as the icon pipeline would.
    icons.append((label, NSImage(contentsOf: out.appendingPathComponent("\(file)-1024.png"))!))
}

// Sheet: per background, one row of 256pt icons and one row of true-size 32 and 16px icons (plus 4x zoom of the 32).
let cell = 300, pad = 40, band = 560
let sheet = bitmap(cell * icons.count + pad * 2, band * 2) {
    for (b, (bg, fg)) in [(NSColor(white: 0.96, alpha: 1), NSColor.black), (NSColor(white: 0.12, alpha: 1), NSColor.white)].enumerated() {
        let y0 = CGFloat(band * (1 - b))
        bg.setFill(); NSRect(x: 0, y: y0, width: CGFloat(cell * icons.count + pad * 2), height: CGFloat(band)).fill()
        for (i, (label, img)) in icons.enumerated() {
            let x = CGFloat(pad + i * cell)
            img.draw(in: NSRect(x: x + 22, y: y0 + 250, width: 256, height: 256))
            let small = bitmap(32, 32) { img.draw(in: NSRect(x: 0, y: 0, width: 32, height: 32)) }
            let tiny = bitmap(16, 16) { img.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16)) }
            NSGraphicsContext.current?.imageInterpolation = .none
            over(small, NSRect(x: x + 60, y: y0 + 100, width: 128, height: 128))  // 32px at 4x, pixels visible
            NSGraphicsContext.current?.imageInterpolation = .high
            over(small, NSRect(x: x + 206, y: y0 + 196, width: 32, height: 32))
            over(tiny, NSRect(x: x + 214, y: y0 + 160, width: 16, height: 16))
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: fg]
            (label as NSString).draw(at: NSPoint(x: x + 60, y: y0 + 520 - 14), withAttributes: attrs)
            let note: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: fg.withAlphaComponent(0.6)]
            ("32px ×4   32   16" as NSString).draw(at: NSPoint(x: x + 60, y: y0 + 64), withAttributes: note)
        }
    }
}
save(sheet, "comparison-sheet.png")
