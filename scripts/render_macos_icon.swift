import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("usage: swift render_macos_icon.swift <iconset-dir>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let iconDefinitions: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = CGFloat(size) * 0.06
    let panelRect = rect.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(size) * 0.24

    let background = NSBezierPath(roundedRect: panelRect, xRadius: radius, yRadius: radius)
    context.saveGState()
    background.addClip()

    let colors = [
        NSColor(calibratedRed: 0.07, green: 0.44, blue: 0.46, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.95, green: 0.74, blue: 0.41, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.98, green: 0.93, blue: 0.86, alpha: 1).cgColor,
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.55, 1.0]
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: panelRect.minX, y: panelRect.maxY),
        end: CGPoint(x: panelRect.maxX, y: panelRect.minY),
        options: []
    )

    let glowRect = CGRect(
        x: panelRect.minX - CGFloat(size) * 0.1,
        y: panelRect.maxY - CGFloat(size) * 0.48,
        width: CGFloat(size) * 0.7,
        height: CGFloat(size) * 0.7
    )
    let glowColor = NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.94, alpha: 0.75).cgColor
    context.setFillColor(glowColor)
    context.fillEllipse(in: glowRect)
    context.restoreGState()

    let framePath = NSBezierPath(roundedRect: panelRect, xRadius: radius, yRadius: radius)
    NSColor.white.withAlphaComponent(0.28).setStroke()
    framePath.lineWidth = max(2, CGFloat(size) * 0.012)
    framePath.stroke()

    let chartInsetX = CGFloat(size) * 0.18
    let chartBaseY = CGFloat(size) * 0.26
    let barWidth = CGFloat(size) * 0.12
    let gap = CGFloat(size) * 0.065
    let barHeights: [CGFloat] = [0.22, 0.36, 0.54]
    let barColors = [
        NSColor.white.withAlphaComponent(0.82),
        NSColor(calibratedRed: 0.95, green: 0.98, blue: 0.98, alpha: 0.86),
        NSColor(calibratedRed: 0.98, green: 0.95, blue: 0.89, alpha: 0.9),
    ]

    for (index, ratio) in barHeights.enumerated() {
        let x = chartInsetX + CGFloat(index) * (barWidth + gap)
        let height = CGFloat(size) * ratio
        let barRect = CGRect(x: x, y: chartBaseY, width: barWidth, height: height)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth * 0.45, yRadius: barWidth * 0.45)
        barColors[index].setFill()
        barPath.fill()
    }

    let linePath = NSBezierPath()
    linePath.move(to: CGPoint(x: chartInsetX - gap * 0.1, y: chartBaseY + CGFloat(size) * 0.14))
    linePath.line(to: CGPoint(x: chartInsetX + barWidth * 0.6, y: chartBaseY + CGFloat(size) * 0.3))
    linePath.line(to: CGPoint(x: chartInsetX + (barWidth + gap) + barWidth * 0.55, y: chartBaseY + CGFloat(size) * 0.26))
    linePath.line(to: CGPoint(x: chartInsetX + 2 * (barWidth + gap) + barWidth * 0.6, y: chartBaseY + CGFloat(size) * 0.62))
    linePath.lineWidth = max(4, CGFloat(size) * 0.032)
    linePath.lineCapStyle = .round
    linePath.lineJoinStyle = .round
    NSColor(calibratedRed: 0.11, green: 0.23, blue: 0.26, alpha: 0.88).setStroke()
    linePath.stroke()

    let dotCenters = [
        CGPoint(x: chartInsetX - gap * 0.1, y: chartBaseY + CGFloat(size) * 0.14),
        CGPoint(x: chartInsetX + barWidth * 0.6, y: chartBaseY + CGFloat(size) * 0.3),
        CGPoint(x: chartInsetX + (barWidth + gap) + barWidth * 0.55, y: chartBaseY + CGFloat(size) * 0.26),
        CGPoint(x: chartInsetX + 2 * (barWidth + gap) + barWidth * 0.6, y: chartBaseY + CGFloat(size) * 0.62),
    ]
    for center in dotCenters {
        let dotRect = CGRect(x: center.x - CGFloat(size) * 0.03, y: center.y - CGFloat(size) * 0.03, width: CGFloat(size) * 0.06, height: CGFloat(size) * 0.06)
        NSColor(calibratedRed: 0.98, green: 0.98, blue: 0.97, alpha: 1).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    let coinRect = CGRect(
        x: panelRect.maxX - CGFloat(size) * 0.26,
        y: panelRect.maxY - CGFloat(size) * 0.28,
        width: CGFloat(size) * 0.14,
        height: CGFloat(size) * 0.14
    )
    let coinPath = NSBezierPath(ovalIn: coinRect)
    NSColor(calibratedRed: 0.12, green: 0.27, blue: 0.29, alpha: 0.92).setFill()
    coinPath.fill()
    let coinInner = CGRect(x: coinRect.minX + coinRect.width * 0.26, y: coinRect.minY + coinRect.height * 0.18, width: coinRect.width * 0.48, height: coinRect.height * 0.64)
    let currencyPath = NSBezierPath(roundedRect: coinInner, xRadius: coinInner.width * 0.2, yRadius: coinInner.width * 0.2)
    NSColor.white.withAlphaComponent(0.95).setStroke()
    currencyPath.lineWidth = max(2, CGFloat(size) * 0.01)
    currencyPath.stroke()

    image.unlockFocus()
    return image
}

func writePNG(image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "RenderIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法生成 PNG"])
    }
    try pngData.write(to: url)
}

for (name, size) in iconDefinitions {
    let url = outputDirectory.appendingPathComponent(name)
    try writePNG(image: drawIcon(size: size), to: url)
}
