#!/usr/bin/env swift
// Draws the Doodlemark app icon at every size an iPad app needs and writes
// the asset catalog's AppIcon.appiconset (PNGs + Contents.json).
//
//   swift scripts/make_app_icon.swift            (from the repo root)
//
// The icon is the app mark from design/Gallery.png (`AppMark` in
// GalleryScreen.swift): an ink square with a tangerine squiggle. The path and
// colors here are the same numbers as `AppMark` and `Theme` (ink #1C1B22,
// tangerine #FF5A1F). Full bleed and opaque: iPadOS rounds the corners itself,
// and the App Store icon must have no alpha. Each size is drawn as vectors at
// its own pixel size (no downscaling blur).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconSlot {
    let idiom: String
    let points: Double
    let scale: Int
    var pixels: Int { Int((points * Double(scale)).rounded()) }
    var sizeText: String { points == points.rounded() ? "\(Int(points))x\(Int(points))" : "\(points)x\(points)" }
    var fileName: String { "AppIcon-\(sizeText.replacingOccurrences(of: "x", with: "-"))@\(scale)x.png" }
}

/// iPad (TARGETED_DEVICE_FAMILY 2): notifications, Settings, Spotlight, the
/// home screen (76 / 83.5 for iPad Pro) and the App Store.
let slots = [
    IconSlot(idiom: "ipad", points: 20, scale: 1), IconSlot(idiom: "ipad", points: 20, scale: 2),
    IconSlot(idiom: "ipad", points: 29, scale: 1), IconSlot(idiom: "ipad", points: 29, scale: 2),
    IconSlot(idiom: "ipad", points: 40, scale: 1), IconSlot(idiom: "ipad", points: 40, scale: 2),
    IconSlot(idiom: "ipad", points: 76, scale: 1), IconSlot(idiom: "ipad", points: 76, scale: 2),
    IconSlot(idiom: "ipad", points: 83.5, scale: 2),
    IconSlot(idiom: "ios-marketing", points: 1024, scale: 1),
]

let ink = (r: 0x1C, g: 0x1B, b: 0x22)
let tangerine = (r: 0xFF, g: 0x5A, b: 0x1F)

func color(_ c: (r: Int, g: Int, b: Int)) -> CGColor {
    CGColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
}

func drawIcon(pixels: Int) -> CGImage {
    let s = CGFloat(pixels)
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // y down, like the SwiftUI `AppMark`.
    context.translateBy(x: 0, y: s)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(color(ink))
    context.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // The squiggle, exactly `AppMark`'s path in unit coordinates.
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    context.move(to: p(0.2, 0.64))
    context.addCurve(to: p(0.5, 0.5), control1: p(0.26, 0.22), control2: p(0.44, 0.26))
    context.addCurve(to: p(0.8, 0.36), control1: p(0.56, 0.74), control2: p(0.74, 0.78))
    context.setStrokeColor(color(tangerine))
    context.setLineWidth(0.11 * s)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let set = root.appendingPathComponent("Doodlemark/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("project.yml").path) else {
    FileHandle.standardError.write(Data("Run this from the repo root (where project.yml is).\n".utf8))
    exit(1)
}
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for old in try FileManager.default.contentsOfDirectory(at: set, includingPropertiesForKeys: nil) where old.pathExtension == "png" {
    try FileManager.default.removeItem(at: old)
}

var images: [[String: String]] = []
for slot in slots {
    try writePNG(drawIcon(pixels: slot.pixels), to: set.appendingPathComponent(slot.fileName))
    images.append(["idiom": slot.idiom, "size": slot.sizeText, "scale": "\(slot.scale)x", "filename": slot.fileName])
    print("\(slot.fileName)  \(slot.pixels)×\(slot.pixels)")
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: set.appendingPathComponent("Contents.json"))
print("Wrote \(slots.count) icons to \(set.path)")
