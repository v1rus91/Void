import AppKit
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -12); sh.set()
NSGradient(colors: [NSColor(red: 0.16, green: 0.08, blue: 0.32, alpha: 1), NSColor(red: 0.03, green: 0.02, blue: 0.09, alpha: 1)])!.draw(in: path, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()
NSGraphicsContext.current?.saveGraphicsState()
path.addClip()
// glow
let c = CGPoint(x: S / 2, y: S / 2)
let glow = CGGradient(colorsSpace: nil, colors: [NSColor(red: 0.85, green: 0.35, blue: 1, alpha: 0.55).cgColor, NSColor.clear.cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: c, startRadius: 150, endCenter: c, endRadius: 420, options: [])
// ring with angular gradient
let ring = CGMutablePath(); ring.addEllipse(in: CGRect(x: c.x - 245, y: c.y - 245, width: 490, height: 490))
ctx.saveGState()
ctx.addPath(ring.copy(strokingWithWidth: 70, lineCap: .round, lineJoin: .round, miterLimit: 1))
ctx.clip()
let cols: [NSColor] = [.systemPink, .systemPurple, .systemBlue, .systemCyan, .systemPink]
let steps = 360
for i in 0..<steps {
    let t = CGFloat(i) / CGFloat(steps)
    let seg = t * CGFloat(cols.count - 1); let k = min(Int(seg), cols.count - 2); let f = seg - CGFloat(k)
    let col = cols[k].blended(withFraction: f, of: cols[k + 1])!
    ctx.setFillColor(col.cgColor)
    let a0 = t * 2 * .pi, a1 = a0 + 2 * .pi / CGFloat(steps) + 0.01
    ctx.move(to: c); ctx.addArc(center: c, radius: 400, startAngle: a0, endAngle: a1, clockwise: false); ctx.fillPath()
}
ctx.restoreGState()
// event horizon
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillEllipse(in: CGRect(x: c.x - 200, y: c.y - 200, width: 400, height: 400))
// glass highlight
NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!.draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
