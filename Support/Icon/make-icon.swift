// Renders the app icon: a tomato-shaped START button nobody has ever pressed.
// Usage: swift make-icon.swift <dir.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// Superellipse approximating Apple's continuous-corner icon shape.
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    for i in 0...360 {
        let t = CGFloat(i) * .pi / 180
        let c = cos(t), s = sin(t)
        let x = r.midX + r.width / 2 * copysign(pow(abs(c), 2 / n), c)
        let y = r.midY + r.height / 2 * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

/// Draws in a 1024pt space; the caller scales to the target size.
func draw(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)

    // Base with drop shadow and a soft vertical gradient.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0.35))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x2B3050)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x454C78), rgb(0x1F2338)], [0, 1]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Button housing.
    let c = CGPoint(x: 512, y: 470)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0.5))
    ctx.addEllipse(in: CGRect(x: c.x - 318, y: c.y - 300, width: 636, height: 600))
    ctx.setFillColor(rgb(0x14172A)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - 300, y: c.y - 282, width: 600, height: 564)); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x9AA0B8), rgb(0x3A3F58)], [0, 1]), start: CGPoint(x: 512, y: c.y + 282), end: CGPoint(x: 512, y: c.y - 282), options: [])
    ctx.restoreGState()

    // Tomato dome.
    let dome = CGRect(x: c.x - 262, y: c.y - 222, width: 524, height: 470)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: rgb(0, 0.45))
    ctx.addEllipse(in: dome); ctx.setFillColor(rgb(0xC8281C)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: dome); ctx.clip()
    ctx.drawRadialGradient(gradient([rgb(0xFF7A5C), rgb(0xE8392A), rgb(0xA8180F)], [0, 0.55, 1]),
                           startCenter: CGPoint(x: dome.midX - 90, y: dome.midY + 110), startRadius: 0,
                           endCenter: CGPoint(x: dome.midX, y: dome.midY), endRadius: 300, options: [.drawsAfterEndLocation])
    ctx.restoreGState()
    // Gloss.
    ctx.addEllipse(in: CGRect(x: dome.minX + 90, y: dome.maxY - 150, width: 170, height: 80))
    ctx.setFillColor(rgb(0xFFFFFF, 0.35)); ctx.fillPath()

    // Calyx: five leaves and a stem.
    let top = CGPoint(x: dome.midX, y: dome.maxY - 26)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: rgb(0, 0.35))
    ctx.setFillColor(rgb(0x3FA34D))
    for angle in stride(from: -80.0, through: 80.0, by: 40.0) {
        ctx.saveGState()
        ctx.translateBy(x: top.x, y: top.y)
        ctx.rotate(by: CGFloat((angle + 180) * .pi / 180))
        let leaf = CGMutablePath()
        leaf.move(to: .zero)
        leaf.addQuadCurve(to: CGPoint(x: 0, y: 120), control: CGPoint(x: 42, y: 50))
        leaf.addQuadCurve(to: .zero, control: CGPoint(x: -42, y: 50))
        ctx.addPath(leaf); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(0x2E7D3A)); ctx.setLineWidth(26); ctx.setLineCap(.round)
    ctx.move(to: top); ctx.addQuadCurve(to: CGPoint(x: top.x + 34, y: top.y + 70), control: CGPoint(x: top.x, y: top.y + 50))
    ctx.strokePath()

    // START label.
    ctx.saveGState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let font = NSFont.systemFont(ofSize: 124, weight: .heavy)
    let label = NSAttributedString(string: "START", attributes: [
        .font: NSFont(descriptor: font.fontDescriptor.withDesign(.rounded)!, size: 124)!,
        .foregroundColor: NSColor.white,
        .kern: 4,
    ])
    let size = label.size()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 0, color: rgb(0x7A0E08, 0.8))
    label.draw(at: CGPoint(x: dome.midX - size.width / 2, y: dome.midY - size.height / 2 - 20))
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()

    // Cobweb from the top-right corner onto the button: nobody has ever pressed it.
    let anchor = CGPoint(x: 860, y: 860)
    let spokes: [CGFloat] = [180, 202, 225, 248, 270].map { $0 * .pi / 180 }
    let reach: CGFloat = 420
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.85)); ctx.setLineCap(.round)
    ctx.setLineWidth(9)
    for a in spokes {
        ctx.move(to: anchor); ctx.addLine(to: CGPoint(x: anchor.x + cos(a) * reach, y: anchor.y + sin(a) * reach))
    }
    ctx.strokePath()
    ctx.setLineWidth(7)
    for r in stride(from: CGFloat(90), through: 400, by: 100) {
        for (a, b) in zip(spokes, spokes.dropFirst()) {
            let p = CGPoint(x: anchor.x + cos(a) * r, y: anchor.y + sin(a) * r)
            let q = CGPoint(x: anchor.x + cos(b) * r, y: anchor.y + sin(b) * r)
            let m = CGPoint(x: anchor.x + cos((a + b) / 2) * r * 0.9, y: anchor.y + sin((a + b) / 2) * r * 0.9)
            ctx.move(to: p); ctx.addQuadCurve(to: q, control: m)
        }
    }
    ctx.strokePath()

    // A spider hanging off the web, waiting.
    let spider = CGPoint(x: 772, y: 430)
    ctx.setLineWidth(4)
    ctx.move(to: CGPoint(x: spider.x, y: 700)); ctx.addLine(to: spider); ctx.strokePath()
    ctx.setStrokeColor(rgb(0x0E1020)); ctx.setLineWidth(7)
    for side: CGFloat in [-1, 1] {
        for (dy, bend) in [(18.0, 30.0), (6.0, 10.0), (-6.0, -10.0), (-18.0, -30.0)] as [(CGFloat, CGFloat)] {
            let hip = CGPoint(x: spider.x, y: spider.y - 34 + dy)
            ctx.move(to: hip)
            ctx.addQuadCurve(to: CGPoint(x: spider.x + side * 52, y: hip.y + bend - 14), control: CGPoint(x: spider.x + side * 36, y: hip.y + bend + 16))
        }
    }
    ctx.strokePath()
    ctx.setFillColor(rgb(0x0E1020))
    ctx.fillEllipse(in: CGRect(x: spider.x - 24, y: spider.y - 70, width: 48, height: 56))
    ctx.fillEllipse(in: CGRect(x: spider.x - 15, y: spider.y - 22, width: 30, height: 28))
    ctx.restoreGState()
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(ctx)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("icon_\(name).png"))
}
