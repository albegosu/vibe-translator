// Renders the app icon into Resources/AppIcon.icns (plus a 1024 px preview).
//
//   swift scripts/make-icon.swift
//
// Dark glass squircle with a blurred aurora glow and two overlapping speech bubbles
// (Ñ → A). Below 64 px the letters are dropped so the bubbles stay legible.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let preview = root.appendingPathComponent("build/AppIcon-preview.png")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// Soft radial blob: the "blurred accent gradient" without a blur filter.
func glow(_ context: CGContext, center: CGPoint, radius: CGFloat, color: NSColor, intensity: CGFloat) {
    let colors = [color.withAlphaComponent(intensity).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) else { return }
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Rounded-rect bubble with a tail, as one path so translucent fills don't double up.
func bubble(_ rect: CGRect, radius: CGFloat, tailOnLeft: Bool) -> NSBezierPath {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    // The tail starts inside the flat part of the bottom edge (clear of the rounded corner)
    // and sweeps outwards and down to a point.
    let side: CGFloat = tailOnLeft ? -1 : 1
    let (w, h) = (rect.width, rect.height)
    let baseX = tailOnLeft ? rect.minX + w * 0.34 : rect.maxX - w * 0.34
    let inner = baseX - side * w * 0.11
    let outer = baseX + side * w * 0.11
    let tip = CGPoint(x: tailOnLeft ? rect.minX + w * 0.12 : rect.maxX - w * 0.12, y: rect.minY - h * 0.2)
    let tail = NSBezierPath()
    tail.move(to: CGPoint(x: inner, y: rect.minY + radius * 0.6))
    tail.line(to: CGPoint(x: inner, y: rect.minY))
    tail.curve(
        to: tip,
        controlPoint1: CGPoint(x: inner, y: rect.minY - h * 0.12),
        controlPoint2: CGPoint(x: tip.x - side * w * 0.06, y: tip.y + h * 0.02)
    )
    tail.curve(
        to: CGPoint(x: outer, y: rect.minY),
        controlPoint1: CGPoint(x: tip.x - side * w * 0.03, y: tip.y + h * 0.08),
        controlPoint2: CGPoint(x: outer, y: rect.minY - h * 0.05)
    )
    tail.line(to: CGPoint(x: outer, y: rect.minY + radius * 0.6))
    tail.close()
    // Mirroring flips the drawing direction; with non-zero winding that would punch a hole.
    path.append(tailOnLeft ? tail.reversed : tail)
    path.windingRule = .nonZero
    return path
}

func drawGlyph(_ glyph: String, in rect: CGRect, size: CGFloat, color: NSColor) {
    let base = NSFont.systemFont(ofSize: size, weight: .bold)
    let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    let text = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: color])
    let bounds = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading])
    text.draw(at: CGPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2 - size * 0.02))
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let detailed = pixels >= 64

    // macOS icon grid: 824 pt squircle centred on a 1024 canvas.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: plate, xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    color(0x0E0E10).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [color(0x1C1C20), color(0x08080A)])!.draw(in: plate, angle: -90)

    // Aurora rising from the bottom edge.
    glow(context, center: CGPoint(x: 330, y: 150), radius: 380, color: color(0x8B5CF6), intensity: 0.85)
    glow(context, center: CGPoint(x: 700, y: 140), radius: 360, color: color(0xEC4899), intensity: 0.75)
    glow(context, center: CGPoint(x: 520, y: 90), radius: 300, color: color(0x22D3EE), intensity: 0.55)
    glow(context, center: CGPoint(x: 860, y: 210), radius: 220, color: color(0xF97316), intensity: 0.45)

    // Glass sheen at the top.
    NSGradient(colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)])!
        .draw(in: CGRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    color(0xFFFFFF, 0.14).setStroke()
    let rim = NSBezierPath(roundedRect: plate.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
    rim.lineWidth = 4
    rim.stroke()

    // Spanish bubble behind (translucent), English bubble in front (solid).
    let back = CGRect(x: 238, y: 470, width: 360, height: 270)
    let front = CGRect(x: 420, y: 300, width: 380, height: 285)
    color(0xFFFFFF, 0.30).setFill()
    bubble(back, radius: 92, tailOnLeft: true).fill()
    if detailed {
        drawGlyph("Ñ", in: back.offsetBy(dx: -40, dy: 18), size: 150, color: color(0xFFFFFF, 0.92))
    }

    NSGraphicsContext.saveGraphicsState()
    let lift = NSShadow()
    lift.shadowColor = color(0x000000, 0.35)
    lift.shadowBlurRadius = 30
    lift.shadowOffset = NSSize(width: 0, height: -10)
    lift.set()
    color(0xF6F6F6).setFill()
    bubble(front, radius: 96, tailOnLeft: false).fill()
    NSGraphicsContext.restoreGraphicsState()
    if detailed {
        drawGlyph("A", in: front, size: 170, color: color(0x111113))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try render(pixels: points * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}
try fm.createDirectory(at: preview.deletingLastPathComponent(), withIntermediateDirectories: true)
try render(pixels: 1024).representation(using: .png, properties: [:])!.write(to: preview)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path) and \(preview.path)")
