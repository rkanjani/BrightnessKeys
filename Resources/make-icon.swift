// Renders the app icon: swift Resources/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon grid: 824pt body centered on a 1024 canvas.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

ctx.saveGState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.black.setFill()
shape.fill()
ctx.restoreGState()

// Night-sky background.
NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.13, blue: 0.32, alpha: 1),
                    NSColor(srgbRed: 0.04, green: 0.05, blue: 0.14, alpha: 1)])!
    .draw(in: shape, angle: -90)

// Monitor outline.
let screen = NSRect(x: 232, y: 330, width: 560, height: 380)
let monitor = NSBezierPath(roundedRect: screen, xRadius: 44, yRadius: 44)
monitor.lineWidth = 30
NSColor.white.withAlphaComponent(0.92).setStroke()
monitor.stroke()
let stand = NSBezierPath()
stand.move(to: NSPoint(x: 512, y: 315))
stand.line(to: NSPoint(x: 512, y: 250))
stand.move(to: NSPoint(x: 420, y: 238))
stand.line(to: NSPoint(x: 604, y: 238))
stand.lineWidth = 30
stand.lineCapStyle = .round
stand.stroke()

// Glowing sun inside the screen.
let center = NSPoint(x: screen.midX, y: screen.midY)
let glow = NSGradient(colors: [NSColor(srgbRed: 1, green: 0.78, blue: 0.25, alpha: 0.55), .clear])!
glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: 190, options: [])

let sunColor = NSColor(srgbRed: 1.0, green: 0.80, blue: 0.27, alpha: 1)
sunColor.setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140)).fill()
sunColor.setStroke()
for i in 0..<8 {
    let angle = CGFloat(i) * .pi / 4
    let ray = NSBezierPath()
    ray.move(to: NSPoint(x: center.x + cos(angle) * 104, y: center.y + sin(angle) * 104))
    ray.line(to: NSPoint(x: center.x + cos(angle) * 140, y: center.y + sin(angle) * 140))
    ray.lineWidth = 26
    ray.lineCapStyle = .round
    ray.stroke()
}

image.unlockFocus()

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = image.size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
