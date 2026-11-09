// Dessine l'icône de NetSpeed (1024 × 1024) : `swift icon.swift icon.png`
import AppKit

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Fond : carré arrondi façon macOS, avec ombre portée.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(20, 24, 48)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()
let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [rgb(38, 46, 92), rgb(14, 17, 36)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
// Fines lignes de « graphique » en fond.
ctx.setStrokeColor(rgb(255, 255, 255, 0.06)); ctx.setLineWidth(4)
for y in stride(from: 260 as CGFloat, through: 780, by: 130) {
    ctx.move(to: CGPoint(x: 100, y: y)); ctx.addLine(to: CGPoint(x: 924, y: y))
}
ctx.strokePath()
ctx.restoreGState()

/// Flèche verticale avec dégradé ; `up` = pointe vers le haut.
func arrow(centerX cx: CGFloat, up: Bool, top: CGColor, bottom: CGColor) {
    let w: CGFloat = 250, shaft: CGFloat = 96, head: CGFloat = 200
    let y0: CGFloat = 250, y1: CGFloat = 774
    let p = CGMutablePath()
    if up {
        p.move(to: CGPoint(x: cx, y: y1))
        p.addLine(to: CGPoint(x: cx + w / 2, y: y1 - head))
        p.addLine(to: CGPoint(x: cx + shaft / 2, y: y1 - head))
        p.addLine(to: CGPoint(x: cx + shaft / 2, y: y0))
        p.addLine(to: CGPoint(x: cx - shaft / 2, y: y0))
        p.addLine(to: CGPoint(x: cx - shaft / 2, y: y1 - head))
        p.addLine(to: CGPoint(x: cx - w / 2, y: y1 - head))
    } else {
        p.move(to: CGPoint(x: cx, y: y0))
        p.addLine(to: CGPoint(x: cx + w / 2, y: y0 + head))
        p.addLine(to: CGPoint(x: cx + shaft / 2, y: y0 + head))
        p.addLine(to: CGPoint(x: cx + shaft / 2, y: y1))
        p.addLine(to: CGPoint(x: cx - shaft / 2, y: y1))
        p.addLine(to: CGPoint(x: cx - shaft / 2, y: y0 + head))
        p.addLine(to: CGPoint(x: cx - w / 2, y: y0 + head))
    }
    p.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: top.copy(alpha: 0.55))
    ctx.addPath(p); ctx.setFillColor(top); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(p); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y1), end: CGPoint(x: 0, y: y0), options: [])
    ctx.restoreGState()
}

arrow(centerX: 375, up: true, top: rgb(120, 255, 190), bottom: rgb(30, 190, 140))   // upload
arrow(centerX: 649, up: false, top: rgb(120, 200, 255), bottom: rgb(60, 120, 255))  // download

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("OK \(out)")
