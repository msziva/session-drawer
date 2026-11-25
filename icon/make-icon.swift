// Draws the app icon and writes it as an .icns file:
//   swift icon/make-icon.swift icon/AppIcon.icns
// A stack of sessions with a terminal in front. Coordinates are on a 1024 point canvas.
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func draw() {
    // Background: the macOS icon shape, 824 points wide on the 1024 canvas.
    let plate = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                             xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    color(0x1c1b22).setFill()
    plate.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x1c1b22), ending: color(0x3d3a47))?.draw(in: plate, angle: 90)

    // The sessions behind, each a little narrower and higher than the one before it.
    func card(_ rect: NSRect, _ fill: NSColor) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 44, yRadius: 44).fill()
    }
    card(NSRect(x: 312, y: 390, width: 400, height: 360), color(0x6b6777))
    card(NSRect(x: 272, y: 330, width: 480, height: 360), color(0xa29eae))
    // The one in front, with a prompt.
    card(NSRect(x: 232, y: 270, width: 560, height: 360), color(0xf4f1ea))

    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 330, y: 525))
    chevron.line(to: NSPoint(x: 435, y: 450))
    chevron.line(to: NSPoint(x: 330, y: 375))
    chevron.lineWidth = 44
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    color(0xd97757).setStroke()
    chevron.stroke()

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 490, y: 375))
    cursor.line(to: NSPoint(x: 620, y: 375))
    cursor.lineWidth = 44
    cursor.lineCapStyle = .round
    color(0x1c1b22).setStroke()
    cursor.stroke()
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    // 1024 points on however many pixels: the drawing scales itself.
    rep.size = NSSize(width: 1024, height: 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: swift make-icon.swift <output.icns>\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset.deletingLastPathComponent())
exit(iconutil.terminationStatus)
