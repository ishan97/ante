// scripts/render-icon.swift — draws Ante's app icon at any size.
//   swift scripts/render-icon.swift <size> <out.png> [1..10]
// 2 (default): the neural chevron — a prompt built from glowing nodes and links. The other
// numbers are the ten concepts explored for it. Drawn, not traced, so every size is crisp.
import AppKit
let size = CGFloat(Int(CommandLine.arguments[1])!)
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let variant = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 2
let u = size / 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext; ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: Int, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a])! }
func grad(_ stops: [(Int, CGFloat, CGFloat)]) -> CGGradient { CGGradient(colorsSpace: space, colors: stops.map { rgb($0.0, $0.1) } as CFArray, locations: stops.map { $0.2 })! }
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }

// Palettes: warm (Ante amber → coral) and cool (cyan → violet), picked per concept.
let warm: [(Int, CGFloat, CGFloat)] = [(0xFFD27A, 1, 0), (0xFF7A59, 1, 1)]
let cool: [(Int, CGFloat, CGFloat)] = [(0x5EE7FF, 1, 0), (0x8B5CF6, 1, 1)]
let warmGlow = 0xFF8A4D, coolGlow = 0x4FB8FF

// Tile
let tile = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186 * u, cornerHeight: 186 * u, transform: nil)
func drawTile(top: Int, bottom: Int, glow: Int, glowAt: CGPoint) {
    ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u, color: CGColor(gray: 0, alpha: 0.35)); ctx.addPath(tilePath); ctx.setFillColor(rgb(bottom)); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
    ctx.drawLinearGradient(grad([(top, 1, 0), (bottom, 1, 1)]), start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.drawRadialGradient(grad([(glow, 0.28, 0), (glow, 0, 1)]), startCenter: glowAt, startRadius: 0, endCenter: glowAt, endRadius: 520 * u, options: [])
    ctx.restoreGState()
}
func finishTile() {
    ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5 * u, dy: 1.5 * u), cornerWidth: 184 * u, cornerHeight: 184 * u, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.08)); ctx.setLineWidth(3 * u); ctx.strokePath()
    ctx.drawLinearGradient(grad([(0xFFFFFF, 0.08, 0), (0xFFFFFF, 0, 1)]), start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.maxY - 200 * u), options: [])
    ctx.restoreGState()
}
func glowStroke(_ path: CGPath, width: CGFloat, colors: [(Int, CGFloat, CGFloat)], from: CGPoint, to: CGPoint, glow: Int, blur: CGFloat = 36, alpha: CGFloat = 0.8, join: CGLineJoin = .round) {
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: blur * u, color: rgb(glow, alpha)); ctx.addPath(path); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(join); ctx.setStrokeColor(rgb(glow, 0.9)); ctx.strokePath(); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(join); ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(grad(colors), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]); ctx.restoreGState()
}
func glowFill(_ path: CGPath, colors: [(Int, CGFloat, CGFloat)], from: CGPoint, to: CGPoint, glow: Int, blur: CGFloat = 36, alpha: CGFloat = 0.8) {
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: blur * u, color: rgb(glow, alpha)); ctx.addPath(path); ctx.setFillColor(rgb(glow, 0.9)); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip(); ctx.drawLinearGradient(grad(colors), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]); ctx.restoreGState()
}
func sparkle(at c: CGPoint, r: CGFloat, pinch: CGFloat = 0.22) -> CGPath {
    let p = CGMutablePath(); let q = r * pinch
    p.move(to: CGPoint(x: c.x, y: c.y + r)); p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + q, y: c.y + q))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + q, y: c.y - q)); p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - q, y: c.y - q))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - q, y: c.y + q)); p.closeSubpath(); return p
}
func dot(_ c: CGPoint, _ r: CGFloat, _ color: Int, glow: CGFloat = 30) {
    ctx.saveGState(); ctx.setShadow(offset: .zero, blur: glow * u, color: rgb(color, 0.9)); ctx.setFillColor(rgb(color)); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ctx.restoreGState()
    ctx.saveGState(); ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ctx.clip()
    ctx.drawRadialGradient(grad([(0xFFFFFF, 0.9, 0), (color, 1, 0.6), (color, 1, 1)]), startCenter: CGPoint(x: c.x - r * 0.3, y: c.y + r * 0.3), startRadius: 0, endCenter: c, endRadius: r * 1.1, options: []); ctx.restoreGState()
}
func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath { CGPath(roundedRect: CGRect(x: x * u, y: y * u, width: w * u, height: h * u), cornerWidth: r * u, cornerHeight: r * u, transform: nil) }
func line(_ pts: [CGPoint]) -> CGPath { let p = CGMutablePath(); p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }; return p }

switch variant {
case 1: // Prompt spark: the `>` and a sparkle where the cursor would be.
    drawTile(top: 0x171A26, bottom: 0x07080E, glow: warmGlow, glowAt: P(640, 330))
    glowStroke(line([P(300, 690), P(520, 512), P(300, 334)]), width: 92 * u, colors: warm, from: P(300, 700), to: P(520, 330), glow: warmGlow)
    glowFill(sparkle(at: P(690, 330), r: 118 * u), colors: [(0xFFF2C6, 1, 0), (0xFFB25C, 1, 1)], from: P(600, 420), to: P(780, 240), glow: warmGlow, blur: 44)
case 2: // Neural chevron: a `>` built from nodes and links.
    drawTile(top: 0x121826, bottom: 0x06080F, glow: coolGlow, glowAt: P(512, 512))
    let nodes = [P(300, 700), P(410, 606), P(520, 512), P(410, 418), P(300, 324)]
    let links = CGMutablePath(); links.move(to: nodes[0]); for n in nodes.dropFirst() { links.addLine(to: n) }
    links.move(to: nodes[1]); links.addLine(to: P(700, 640)); links.move(to: nodes[3]); links.addLine(to: P(700, 384)); links.move(to: nodes[2]); links.addLine(to: P(760, 512))
    glowStroke(links, width: 14 * u, colors: cool, from: P(300, 700), to: P(760, 320), glow: coolGlow, blur: 20, alpha: 0.5)
    for n in nodes { dot(n, 34 * u, 0x8B5CF6) }
    for n in [P(700, 640), P(700, 384), P(760, 512)] { dot(n, 22 * u, 0x5EE7FF) }
    dot(nodes[2], 46 * u, 0xE0F7FF)
case 3: // Cursor core: a cursor block with two electron orbits — the atom of the terminal.
    drawTile(top: 0x181A2A, bottom: 0x07080E, glow: warmGlow, glowAt: P(512, 512))
    for angle in [-0.55, 0.55] {
        let t = CGAffineTransform(translationX: 512 * u, y: 512 * u).rotated(by: angle).scaledBy(x: 1, y: 0.34)
        let orbit = CGMutablePath(); orbit.addEllipse(in: CGRect(x: -330 * u, y: -330 * u, width: 660 * u, height: 660 * u), transform: t)
        glowStroke(orbit, width: 16 * u, colors: [(0xFFD27A, 0.9, 0), (0xFF7A59, 0.9, 1)], from: P(200, 700), to: P(820, 320), glow: warmGlow, blur: 18, alpha: 0.5)
    }
    glowFill(rr(448, 392, 128, 240, 22), colors: [(0xFFF2C6, 1, 0), (0xFFB25C, 1, 1)], from: P(448, 632), to: P(576, 392), glow: warmGlow, blur: 50)
    dot(P(512 + 330 * cos(1.1) * 0.85, 512 + 330 * sin(1.1) * 0.34 - 60), 20 * u, 0xFFF0C0)
case 4: // Aperture: a gradient aperture opening on a bright core.
    drawTile(top: 0x12141F, bottom: 0x06070C, glow: coolGlow, glowAt: P(512, 512))
    for (i, r) in [(0, 330), (1, 250), (2, 170)] {
        let p = CGMutablePath(); let a0 = CGFloat(0.12 + Double(i) * 0.35), a1 = a0 + .pi * 1.55
        p.addArc(center: P(512, 512), radius: CGFloat(r) * u, startAngle: a0, endAngle: a1, clockwise: false)
        glowStroke(p, width: 46 * u, colors: [(0x5EE7FF, 1, 0), (0x8B5CF6, 1, 0.6), (0xFF5E8A, 1, 1)], from: P(200, 200), to: P(820, 820), glow: coolGlow, blur: 22, alpha: 0.45)
    }
    dot(P(512, 512), 64 * u, 0xE8FBFF, glow: 60)
case 5: // Signal prompt: a chevron with an AI waveform running through it.
    drawTile(top: 0x171A26, bottom: 0x07080E, glow: warmGlow, glowAt: P(512, 512))
    glowStroke(line([P(280, 690), P(480, 512), P(280, 334)]), width: 84 * u, colors: warm, from: P(280, 700), to: P(480, 330), glow: warmGlow)
    let wave = CGMutablePath(); wave.move(to: P(520, 512))
    for i in 1...48 { let x = 520 + CGFloat(i) * 5.2; let amp: CGFloat = (i > 8 && i < 40) ? (i > 16 && i < 32 ? 110 : 55) : 18; wave.addLine(to: P(x, 512 + amp * sin(CGFloat(i) * 0.62))) }
    glowStroke(wave, width: 26 * u, colors: [(0xFFD27A, 1, 0), (0xFF5E8A, 1, 1)], from: P(520, 512), to: P(770, 512), glow: warmGlow, blur: 24)
case 6: // Twin blocks: a human cursor and an AI cursor side by side, the AI one lit.
    drawTile(top: 0x171A26, bottom: 0x07080E, glow: warmGlow, glowAt: P(600, 470))
    ctx.saveGState(); ctx.addPath(rr(300, 360, 150, 300, 30)); ctx.setFillColor(rgb(0xFFFFFF, 0.16)); ctx.fillPath(); ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(rr(300, 360, 150, 300, 30)); ctx.setStrokeColor(rgb(0xFFFFFF, 0.35)); ctx.setLineWidth(6 * u); ctx.strokePath(); ctx.restoreGState()
    glowFill(rr(500, 360, 150, 300, 30), colors: [(0xFFE29A, 1, 0), (0xFF7A59, 1, 1)], from: P(500, 660), to: P(650, 360), glow: warmGlow, blur: 50)
    glowFill(sparkle(at: P(700, 690), r: 62 * u), colors: [(0xFFF6DA, 1, 0), (0xFFC46B, 1, 1)], from: P(650, 740), to: P(750, 640), glow: warmGlow, blur: 30)
case 7: // Bracketed spirit: `[ ]` with a glowing presence inside.
    drawTile(top: 0x14172A, bottom: 0x06070E, glow: coolGlow, glowAt: P(512, 512))
    let lb = line([P(360, 330), P(280, 330), P(280, 694), P(360, 694)]), rb = line([P(664, 330), P(744, 330), P(744, 694), P(664, 694)])
    for b in [lb, rb] { glowStroke(b, width: 56 * u, colors: [(0xC9D6FF, 1, 0), (0x8B5CF6, 1, 1)], from: P(280, 700), to: P(744, 330), glow: coolGlow, blur: 18, alpha: 0.5, join: .miter) }
    glowFill(sparkle(at: P(512, 512), r: 132 * u, pinch: 0.26), colors: [(0xFFFFFF, 1, 0), (0x5EE7FF, 1, 1)], from: P(420, 600), to: P(600, 420), glow: coolGlow, blur: 60)
case 8: // Slash: a bold diagonal with a break, and the spark that fills it.
    drawTile(top: 0x171A26, bottom: 0x07080E, glow: warmGlow, glowAt: P(560, 560))
    glowStroke(line([P(330, 300), P(470, 470)]), width: 110 * u, colors: warm, from: P(330, 300), to: P(700, 720), glow: warmGlow, blur: 26)
    glowStroke(line([P(560, 560), P(700, 724)]), width: 110 * u, colors: warm, from: P(330, 300), to: P(700, 720), glow: warmGlow, blur: 26)
    glowFill(sparkle(at: P(515, 515), r: 74 * u), colors: [(0xFFFFFF, 1, 0), (0xFFE29A, 1, 1)], from: P(460, 570), to: P(570, 460), glow: 0xFFF0C0, blur: 46)
case 9: // Terminal window, reduced: a top bar of three lights, a prompt, and an AI reply glowing.
    drawTile(top: 0x171A26, bottom: 0x07080E, glow: warmGlow, glowAt: P(600, 420))
    ctx.saveGState(); ctx.addPath(rr(232, 232, 560, 560, 90)); ctx.setFillColor(rgb(0x000000, 0.35)); ctx.fillPath(); ctx.setStrokeColor(rgb(0xFFFFFF, 0.14)); ctx.setLineWidth(6 * u); ctx.addPath(rr(232, 232, 560, 560, 90)); ctx.strokePath(); ctx.restoreGState()
    for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() { ctx.setFillColor(rgb(c)); ctx.fillEllipse(in: CGRect(x: (300 + CGFloat(i) * 58) * u, y: 700 * u, width: 34 * u, height: 34 * u)) }
    glowStroke(line([P(318, 600), P(392, 540), P(318, 480)]), width: 34 * u, colors: [(0xFFFFFF, 0.85, 0), (0xFFFFFF, 0.85, 1)], from: .zero, to: P(1, 1), glow: 0xFFFFFF, blur: 6, alpha: 0.15)
    glowFill(rr(430, 512, 250, 46, 23), colors: warm, from: P(430, 512), to: P(680, 512), glow: warmGlow, blur: 34)
    glowFill(rr(320, 400, 320, 46, 23), colors: [(0xFF7A59, 1, 0), (0xC03DF5, 1, 1)], from: P(320, 400), to: P(640, 400), glow: 0xC03DF5, blur: 34)
    glowFill(sparkle(at: P(700, 423), r: 44 * u), colors: [(0xFFFFFF, 1, 0), (0xE7B2FF, 1, 1)], from: P(670, 450), to: P(730, 396), glow: 0xC03DF5, blur: 24)
case 10: // Constellation A: the A of Ante as three stars joined by light, the apex burning brightest.
    drawTile(top: 0x121626, bottom: 0x06070F, glow: warmGlow, glowAt: P(512, 640))
    let apex = P(512, 700), l = P(300, 340), r = P(724, 340), ml = P(406, 520), mr = P(618, 520)
    glowStroke(line([l, apex, r]), width: 20 * u, colors: [(0xFFD27A, 0.95, 0), (0xFF7A59, 0.95, 1)], from: P(300, 340), to: P(724, 700), glow: warmGlow, blur: 22, alpha: 0.5)
    glowStroke(line([ml, mr]), width: 14 * u, colors: [(0xFFD27A, 0.7, 0), (0xFF7A59, 0.7, 1)], from: ml, to: mr, glow: warmGlow, blur: 16, alpha: 0.4)
    for n in [l, r] { dot(n, 36 * u, 0xFF8A59) }
    for n in [ml, mr] { dot(n, 26 * u, 0xFFC46B) }
    glowFill(sparkle(at: apex, r: 96 * u), colors: [(0xFFFFFF, 1, 0), (0xFFD27A, 1, 1)], from: P(450, 760), to: P(580, 640), glow: 0xFFE29A, blur: 50)
default: break
}
finishTile()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
