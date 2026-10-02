import AppKit
import CoreGraphics
import Foundation

let side = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
    isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Could not create icon bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext
let bounds = CGRect(x: 0, y: 0, width: side, height: side)
context.setFillColor(CGColor(red: 0.024, green: 0.027, blue: 0.031, alpha: 1))
context.fill(bounds)

let space = CGColorSpaceCreateDeviceRGB()
let ground = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.04, green: 0.14, blue: 0.23, alpha: 0.7),
    CGColor(red: 0.024, green: 0.027, blue: 0.031, alpha: 0),
] as CFArray, locations: [0, 1])!
context.drawRadialGradient(ground, startCenter: CGPoint(x: 700, y: 760), startRadius: 0,
    endCenter: CGPoint(x: 700, y: 760), endRadius: 690, options: [])

let route = CGMutablePath()
route.move(to: CGPoint(x: 278, y: 784))
route.addLine(to: CGPoint(x: 278, y: 395))
route.addCurve(to: CGPoint(x: 370, y: 303), control1: CGPoint(x: 278, y: 338),
    control2: CGPoint(x: 313, y: 303))
route.addLine(to: CGPoint(x: 750, y: 303))

func stroke(_ width: CGFloat, color: CGColor) {
    context.addPath(route)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setStrokeColor(color)
    context.strokePath()
}

stroke(104, color: CGColor(red: 0, green: 0.62, blue: 0.98, alpha: 0.13))
stroke(70, color: CGColor(red: 0, green: 0.62, blue: 0.98, alpha: 0.18))
stroke(50, color: CGColor(red: 0, green: 0.62, blue: 0.98, alpha: 1))

for point in [CGPoint(x: 278, y: 784), CGPoint(x: 750, y: 303)] {
    context.setFillColor(CGColor(red: 0.025, green: 0.045, blue: 0.06, alpha: 1))
    context.fillEllipse(in: CGRect(x: point.x - 41, y: point.y - 41, width: 82, height: 82))
    context.setFillColor(CGColor(red: 0.96, green: 0.98, blue: 1, alpha: 1))
    context.fillEllipse(in: CGRect(x: point.x - 23, y: point.y - 23, width: 46, height: 46))
}

graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments.dropFirst().first ??
    "Locomate/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let destination = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
    withIntermediateDirectories: true)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try data.write(to: destination, options: .atomic)
