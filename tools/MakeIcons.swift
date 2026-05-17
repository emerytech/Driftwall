// Generates AppIcon.icns and a template MenuBar.pdf with no external assets.
// Run: swift tools/MakeIcons.swift <outputDir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderAppIcon(pixel: Int) -> NSBitmapImageRep {
    let s = CGFloat(pixel)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()

    // Twilight → teal sky.
    let top = NSColor(calibratedRed: 0.23, green: 0.22, blue: 0.55, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.12, green: 0.70, blue: 0.69, alpha: 1)
    NSGradient(starting: top, ending: bottom)!.draw(in: rect, angle: -90)

    // Soft sun.
    NSColor(calibratedRed: 1, green: 0.93, blue: 0.78, alpha: 0.85).setFill()
    NSBezierPath(ovalIn: CGRect(x: rect.minX + rect.width * 0.60,
                                y: rect.minY + rect.height * 0.62,
                                width: rect.width * 0.16,
                                height: rect.width * 0.16)).fill()

    // Drifting parallax hills.
    func hill(level: CGFloat, amp: CGFloat, color: NSColor, phase: CGFloat) {
        let baseY = rect.minY + rect.height * level
        let p = NSBezierPath()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.line(to: CGPoint(x: rect.minX, y: baseY))
        let steps = 80
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = rect.minX + t * rect.width
            let y = baseY + sin(t * .pi * 2 + phase) * amp
            p.line(to: CGPoint(x: x, y: y))
        }
        p.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.close()
        color.setFill()
        p.fill()
    }
    hill(level: 0.42, amp: s * 0.05,
         color: NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.62, alpha: 0.55), phase: 0.4)
    hill(level: 0.32, amp: s * 0.06,
         color: NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.52, alpha: 0.78), phase: 1.6)
    hill(level: 0.22, amp: s * 0.05,
         color: NSColor(calibratedRed: 0.05, green: 0.28, blue: 0.40, alpha: 0.96), phase: 2.7)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

// Build .iconset then convert with iconutil.
let iconset = (outDir as NSString).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    writePNG(renderAppIcon(pixel: px), to: iconset + "/" + name + ".png")
}
let conv = Process()
conv.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
conv.arguments = ["-c", "icns", iconset, "-o", outDir + "/AppIcon.icns"]
try! conv.run()
conv.waitUntilExit()
try? fm.removeItem(atPath: iconset)

// Monochrome template glyph for the menu bar (3 drifting waves), as PDF
// so it stays crisp at any scale.
func writeMenuBarPDF(to path: String) {
    let side: CGFloat = 18
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: side, height: side)
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineCap(.round)
    ctx.setLineWidth(1.6)
    let rows: [CGFloat] = [12.5, 9.0, 5.5]
    for (idx, y) in rows.enumerated() {
        let phase = CGFloat(idx) * 0.9
        let steps = 48
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = 2.5 + t * 13.0
            let yy = y + sin(t * .pi * 2 + phase) * 1.4
            if i == 0 { ctx.move(to: CGPoint(x: x, y: yy)) }
            else { ctx.addLine(to: CGPoint(x: x, y: yy)) }
        }
        ctx.strokePath()
    }
    ctx.endPDFPage()
    ctx.closePDF()
    try! (data as Data).write(to: URL(fileURLWithPath: path))
}
writeMenuBarPDF(to: outDir + "/MenuBar.pdf")

print("Icons written to \(outDir)")
