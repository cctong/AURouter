#!/usr/bin/env swift
import AppKit
import Foundation

let projectRoot = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let support = projectRoot.appendingPathComponent("Support")
let iconset = support.appendingPathComponent("AppIcon.iconset")
let masterURL = support.appendingPathComponent("AppIcon-1024.png")
let icnsURL = support.appendingPathComponent("AURouter.icns")

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to allocate icon bitmap")
    }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Unable to create graphics context")
    }
    NSGraphicsContext.current = context
    let ctx = context.cgContext
    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)

    let s = size
    let space = CGColorSpaceCreateDeviceRGB()
    let top = CGColor(srgbRed: 0.18, green: 0.27, blue: 0.40, alpha: 1)
    let bottom = CGColor(srgbRed: 0.05, green: 0.08, blue: 0.13, alpha: 1)
    var locations: [CGFloat] = [0, 1]
    let background = CGGradient(
        colorsSpace: space,
        colors: [top, bottom] as CFArray,
        locations: &locations
    )!
    ctx.drawLinearGradient(
        background,
        start: CGPoint(x: s * 0.15, y: s),
        end: CGPoint(x: s * 0.9, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    let mint = NSColor(srgbRed: 0.30, green: 0.90, blue: 0.74, alpha: 1)
    let mintGlow = NSColor(srgbRed: 0.30, green: 0.90, blue: 0.74, alpha: 0.35)
    let metal = NSColor(srgbRed: 0.86, green: 0.90, blue: 0.94, alpha: 1)
    let well = NSColor(srgbRed: 0.07, green: 0.10, blue: 0.14, alpha: 1)
    let moduleFill = NSColor(srgbRed: 0.12, green: 0.19, blue: 0.28, alpha: 1)
    let moduleEdge = NSColor(srgbRed: 0.38, green: 0.52, blue: 0.64, alpha: 1)

    let midY = s * 0.50
    let stroke = max(s * 0.048, 1.25)
    let jackOuter = s * 0.118
    let left = CGPoint(x: s * 0.20, y: midY)
    let right = CGPoint(x: s * 0.80, y: midY)
    let box = CGRect(
        x: s * 0.355,
        y: s * 0.30,
        width: s * 0.29,
        height: s * 0.40
    )

    ctx.saveGState()
    ctx.setStrokeColor(mintGlow.cgColor)
    ctx.setLineWidth(stroke * 2.4)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: left.x + jackOuter * 0.55, y: midY))
    ctx.addLine(to: CGPoint(x: box.minX, y: midY))
    ctx.move(to: CGPoint(x: box.maxX, y: midY))
    ctx.addLine(to: CGPoint(x: right.x - jackOuter * 0.55, y: midY))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.setStrokeColor(mint.cgColor)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: left.x + jackOuter * 0.55, y: midY))
    ctx.addLine(to: CGPoint(x: box.minX, y: midY))
    ctx.move(to: CGPoint(x: box.maxX, y: midY))
    ctx.addLine(to: CGPoint(x: right.x - jackOuter * 0.55, y: midY))
    ctx.strokePath()

    let radius = s * 0.055
    let module = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.45))
    ctx.setFillColor(moduleFill.cgColor)
    ctx.addPath(module)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    ctx.addPath(module)
    ctx.setStrokeColor(moduleEdge.cgColor)
    ctx.setLineWidth(max(s * 0.012, 1))
    ctx.strokePath()

    let inset = box.insetBy(dx: s * 0.045, dy: s * 0.11)
    ctx.setStrokeColor(mint.cgColor)
    ctx.setLineWidth(max(s * 0.028, 1.1))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let waves = 12
    ctx.move(to: CGPoint(x: inset.minX, y: inset.midY))
    for i in 0...waves {
        let t = CGFloat(i) / CGFloat(waves)
        let x = inset.minX + inset.width * t
        let y = inset.midY + sin(t * .pi * 2.0) * inset.height * 0.38
        ctx.addLine(to: CGPoint(x: x, y: y))
    }
    ctx.strokePath()

    if size >= 64 {
        let dotR = s * 0.012
        let dotsY = box.maxY - s * 0.055
        let startX = box.midX - s * 0.04
        for i in 0..<3 {
            let x = startX + CGFloat(i) * s * 0.04
            ctx.setFillColor(mint.withAlphaComponent(i == 1 ? 1 : 0.45).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - dotR, y: dotsY - dotR, width: dotR * 2, height: dotR * 2))
        }
    }

    func drawJack(at center: CGPoint) {
        let outer = jackOuter
        ctx.setFillColor(well.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        ctx.setStrokeColor(metal.cgColor)
        ctx.setLineWidth(max(s * 0.018, 1))
        ctx.strokeEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
        let ring = outer * 0.62
        ctx.setStrokeColor(mint.cgColor)
        ctx.setLineWidth(max(s * 0.022, 1))
        ctx.strokeEllipse(in: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2))
        let hole = outer * 0.28
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2))
    }

    drawJack(at: left)
    drawJack(at: right)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func pngData(_ rep: NSBitmapImageRep) -> Data {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode PNG")
    }
    return data
}

try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
let master = drawIcon(size: 1024)
try pngData(master).write(to: masterURL)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for entry in sizes {
    let image = drawIcon(size: CGFloat(entry.pixels))
    try pngData(image).write(to: iconset.appendingPathComponent(entry.name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed (\(iconutil.terminationStatus))")
}


try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.removeItem(at: masterURL)

print(icnsURL.path)
