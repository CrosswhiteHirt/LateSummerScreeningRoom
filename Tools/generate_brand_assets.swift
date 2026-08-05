import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("GameTemplate/GameTemplate/Assets.xcassets")
let backgroundURL = root.appendingPathComponent("material/环境参考图/主页背景.png")

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let data = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: data),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "BrandAssets", code: 1)
    }
    try png.write(to: url)
}

func makeTitleImage() throws {
    let size = NSSize(width: 900, height: 250)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.7)
    shadow.shadowBlurRadius = 12
    shadow.shadowOffset = NSSize(width: 0, height: -3)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = "夏末放映室" as NSString
    title.draw(in: NSRect(x: 0, y: 85, width: 900, height: 110), withAttributes: [
        .font: NSFont.systemFont(ofSize: 78, weight: .semibold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
        .shadow: shadow
    ])
    let subtitle = "THE END-OF-SUMMER SCREENING ROOM" as NSString
    subtitle.draw(in: NSRect(x: 0, y: 48, width: 900, height: 38), withAttributes: [
        .font: NSFont.systemFont(ofSize: 18, weight: .medium),
        .foregroundColor: NSColor(calibratedRed: 0.76, green: 0.90, blue: 0.98, alpha: 0.95),
        .kern: 2.2,
        .paragraphStyle: paragraph,
        .shadow: shadow
    ])
    image.unlockFocus()
    let set = catalog.appendingPathComponent("LaunchTitle.imageset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    try writePNG(image, to: set.appendingPathComponent("launch_title.png"))
}

func makeIcon() throws {
    guard let source = NSImage(contentsOf: backgroundURL) else { throw NSError(domain: "BrandAssets", code: 2) }
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    let sourceRatio = source.size.width / source.size.height
    let targetRatio = size.width / size.height
    var drawRect = NSRect(origin: .zero, size: size)
    if sourceRatio < targetRatio {
        drawRect.size.height = size.width / sourceRatio
        drawRect.origin.y = (size.height - drawRect.height) / 2
    } else {
        drawRect.size.width = size.height * sourceRatio
        drawRect.origin.x = (size.width - drawRect.width) / 2
    }
    source.draw(in: drawRect)
    let gradient = NSGradient(colors: [NSColor.clear, NSColor(calibratedRed: 0.01, green: 0.05, blue: 0.10, alpha: 0.75)])!
    gradient.draw(in: NSRect(origin: .zero, size: size), angle: -90)
    NSColor(calibratedRed: 0.68, green: 0.90, blue: 1, alpha: 0.92).setStroke()
    let beam = NSBezierPath()
    beam.move(to: NSPoint(x: 182, y: 316))
    beam.line(to: NSPoint(x: 790, y: 650))
    beam.lineWidth = 30
    beam.lineCapStyle = .round
    beam.stroke()
    NSColor(calibratedWhite: 0.03, alpha: 0.94).setFill()
    NSBezierPath(ovalIn: NSRect(x: 80, y: 205, width: 250, height: 250)).fill()
    NSColor(calibratedRed: 0.55, green: 0.82, blue: 0.95, alpha: 1).setStroke()
    for center in [NSPoint(x: 165, y: 350), NSPoint(x: 248, y: 350), NSPoint(x: 165, y: 270), NSPoint(x: 248, y: 270)] {
        let hole = NSBezierPath(ovalIn: NSRect(x: center.x - 27, y: center.y - 27, width: 54, height: 54))
        hole.lineWidth = 15
        hole.stroke()
    }
    let ring = NSBezierPath(ovalIn: NSRect(x: 95, y: 220, width: 220, height: 220))
    ring.lineWidth = 16
    ring.stroke()
    image.unlockFocus()
    let set = catalog.appendingPathComponent("AppIcon.appiconset")
    try writePNG(image, to: set.appendingPathComponent("AppIcon-1024.png"))
}

try makeTitleImage()
try makeIcon()
print("Generated launch title and app icon")
