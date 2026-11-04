import AppKit
// Puts a picture on the clipboard, the way a screenshot or a copy out of
// Preview does — PNG and TIFF, no text — for a paste test by hand or script:
//   swift tests/pasteboard-image.swift            a 1200×700 picture at 2× (600×350 points)
//   swift tests/pasteboard-image.swift tall       a 600×1600 one, to see the height cap
// Also writes the same PNG to the path in $OUT, when set, for a drop or a fixture.
let tall = CommandLine.arguments.contains("tall")
let pixels = tall ? CGSize(width: 600, height: 1600) : CGSize(width: 1200, height: 700)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
// Two points per pixel: the picture is 600×350 points on a Retina Mac.
rep.size = NSSize(width: pixels.width / 2, height: pixels.height / 2)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let bounds = NSRect(origin: .zero, size: rep.size)
NSGradient(colors: [NSColor(calibratedRed: 0.16, green: 0.24, blue: 0.52, alpha: 1),
                    NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.56, alpha: 1),
                    NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.38, alpha: 1)])!
    .draw(in: bounds, angle: tall ? 90 : 20)
// A few shapes, so a scale is easy to judge by eye.
NSColor.white.withAlphaComponent(0.85).setFill()
for i in 0..<6 {
    let d = CGFloat(18 + i * 9)
    NSBezierPath(ovalIn: NSRect(x: 30 + CGFloat(i) * 80, y: bounds.height - 40 - d, width: d, height: d)).fill()
}
let text = "a picture, \(Int(pixels.width))×\(Int(pixels.height)) px"
(text as NSString).draw(at: NSPoint(x: 30, y: 28), withAttributes: [
    .font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white])
NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
let tiff = rep.tiffRepresentation!
let pb = NSPasteboard.general
pb.clearContents()
pb.declareTypes([.png, .tiff], owner: nil)
pb.setData(png, forType: .png)
pb.setData(tiff, forType: .tiff)
if let out = ProcessInfo.processInfo.environment["OUT"], !out.isEmpty {
    try! png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
print("clipboard set: \(Int(pixels.width))×\(Int(pixels.height)) px")
