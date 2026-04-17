import AppKit

// Generates AppIcon.icns for SpaceMan: the standard Jorvik blue-gradient
// rounded-square badge with a stylised astronaut helmet glyph on top.
// Replace by dropping your own AppIcon.icns next to this file.

let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
let outDir = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: outDir)
try! FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // Background: Jorvik blue gradient, rounded square
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22
    let clipPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    clipPath.addClip()

    let bg = NSGradient(colors: [
        NSColor(srgbRed: 0.18, green: 0.36, blue: 0.56, alpha: 1.0),
        NSColor(srgbRed: 0.08, green: 0.18, blue: 0.32, alpha: 1.0),
    ])!
    bg.draw(in: rect, angle: -60)

    // Helmet geometry centred in the frame.
    let centre = NSPoint(x: size / 2, y: size / 2)
    let domeRadius = size * 0.32

    // Subtle ground-shadow ellipse under the helmet
    let shadow = NSBezierPath(
        ovalIn: NSRect(
            x: centre.x - domeRadius * 1.05,
            y: centre.y - domeRadius * 1.1,
            width: domeRadius * 2.1,
            height: domeRadius * 0.35
        )
    )
    NSColor(white: 0.0, alpha: 0.22).setFill()
    shadow.fill()

    // Neck ring — thin horizontal bar behind the dome bottom
    let ringHeight = domeRadius * 0.22
    let ringRect = NSRect(
        x: centre.x - domeRadius * 0.85,
        y: centre.y - domeRadius * 1.02,
        width: domeRadius * 1.7,
        height: ringHeight
    )
    let ringPath = NSBezierPath(roundedRect: ringRect, xRadius: ringHeight * 0.4, yRadius: ringHeight * 0.4)
    NSColor(srgbRed: 0.78, green: 0.82, blue: 0.86, alpha: 1.0).setFill()
    ringPath.fill()
    // Ring highlight
    let ringHL = NSBezierPath(rect: NSRect(
        x: ringRect.minX + ringRect.width * 0.08,
        y: ringRect.minY + ringRect.height * 0.62,
        width: ringRect.width * 0.84,
        height: ringRect.height * 0.18
    ))
    NSColor(white: 1.0, alpha: 0.55).setFill()
    ringHL.fill()

    // Dome — white sphere with a soft radial shade for depth
    let domeRect = NSRect(
        x: centre.x - domeRadius,
        y: centre.y - domeRadius,
        width: domeRadius * 2,
        height: domeRadius * 2
    )
    let domePath = NSBezierPath(ovalIn: domeRect)

    NSGraphicsContext.saveGraphicsState()
    domePath.addClip()
    let domeGrad = NSGradient(colors: [
        NSColor(white: 1.00, alpha: 1.0),
        NSColor(white: 0.82, alpha: 1.0),
    ])!
    // Highlight from upper-left, shadow toward lower-right
    domeGrad.draw(
        fromCenter: NSPoint(x: centre.x - domeRadius * 0.35, y: centre.y + domeRadius * 0.35),
        radius: 0,
        toCenter: centre,
        radius: domeRadius * 1.1,
        options: []
    )
    NSGraphicsContext.restoreGraphicsState()

    // Visor — dark tinted oval inset inside the dome, slightly upper-half
    let visorW = domeRadius * 1.45
    let visorH = domeRadius * 0.95
    let visorRect = NSRect(
        x: centre.x - visorW / 2,
        y: centre.y - visorH * 0.35,
        width: visorW,
        height: visorH
    )
    let visorPath = NSBezierPath(ovalIn: visorRect)

    NSGraphicsContext.saveGraphicsState()
    visorPath.addClip()
    let visorGrad = NSGradient(colors: [
        NSColor(srgbRed: 0.05, green: 0.10, blue: 0.18, alpha: 1.0),   // deep near-black
        NSColor(srgbRed: 0.12, green: 0.28, blue: 0.45, alpha: 1.0),   // mid blue
        NSColor(srgbRed: 0.20, green: 0.52, blue: 0.78, alpha: 1.0),   // bright reflection
    ])!
    visorGrad.draw(in: visorRect, angle: -80)
    NSGraphicsContext.restoreGraphicsState()

    // Visor highlight — a slim crescent on the upper-left
    let hlRect = NSRect(
        x: visorRect.minX + visorRect.width * 0.15,
        y: visorRect.minY + visorRect.height * 0.55,
        width: visorRect.width * 0.40,
        height: visorRect.height * 0.22
    )
    let hl = NSBezierPath(ovalIn: hlRect)
    NSColor(white: 1.0, alpha: 0.55).setFill()
    hl.fill()

    // Tiny secondary highlight dot
    let dotSize = domeRadius * 0.10
    let dotRect = NSRect(
        x: visorRect.minX + visorRect.width * 0.68,
        y: visorRect.minY + visorRect.height * 0.30,
        width: dotSize,
        height: dotSize
    )
    NSColor(white: 1.0, alpha: 0.70).setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render PNG at size \(size)")
    }

    // iconset layout: write at 1x, and as @2x for the half-size too.
    let oneX = outDir.appendingPathComponent("icon_\(Int(size))x\(Int(size)).png")
    try! png.write(to: oneX)
    if size >= 32 {
        let halfSize = Int(size) / 2
        let twoX = outDir.appendingPathComponent("icon_\(halfSize)x\(halfSize)@2x.png")
        try! png.write(to: twoX)
    }
}

// Compile into .icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "AppIcon.iconset", "-o", "AppIcon.icns"]
try! task.run()
task.waitUntilExit()

try? FileManager.default.removeItem(at: outDir)

print("Generated AppIcon.icns")
