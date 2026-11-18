import CoreText
import PencilKit
import UIKit
import WebKit
@testable import Doodlemark

/// What one gate case draws: the same data the exporter gets.
struct GateScene {
    var shapes: [LogoShape] = []
    var ink = PKDrawing()
    var text: LogoText?
}

/// A 1024×1024 RGBA8 sRGB bitmap composited on white. Both renders become one
/// of these, so the comparison never depends on how each image was encoded.
struct Bitmap {
    let side: Int
    private(set) var bytes: [UInt8]   // RGBA, row 0 = top

    init(side: Int, bytes: [UInt8]) {
        self.side = side
        self.bytes = bytes
    }

    /// Draws `image` into a `side × side` sRGB bitmap over white.
    init(_ image: CGImage, side: Int = GateConfig.renderSide) {
        self.side = side
        var bytes = [UInt8](repeating: 255, count: side * side * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        self.bytes = bytes
    }

    func rgb(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let i = (y * side + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }

    func cgImage() -> CGImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func pngData() -> Data {
        UIImage(cgImage: cgImage()).pngData()!
    }
}

// MARK: - Native reference render

/// The "what the canvas shows" side: PencilKit's own stroke renderer, Core
/// Graphics for shapes, and `CTLineDraw` for text. `CTLineDraw` is deliberately
/// independent of `GlyphPaths`' outline extraction, so glyph bugs show up as a diff.
@MainActor
enum NativeRenderer {
    static func render(_ scene: GateScene) throws -> Bitmap {
        let side = CGFloat(GateConfig.renderSide)
        let rect = CGRect(x: 0, y: 0, width: side, height: side)

        // PencilKit adapts ink colors for dark mode, so pin the light appearance.
        var inkImage = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            inkImage = scene.ink.image(from: rect, scale: 1)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard   // sRGB, 8 bits per channel

        var textError: Error?
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            cg.fill(rect)

            // Same layer order as the SVG: Shapes, Ink, Text.
            for shape in scene.shapes {
                cg.addPath(ShapeGeometry.path(for: shape))
                cg.setFillColor(shape.fill.cgColor)
                cg.fillPath()
            }

            inkImage.draw(in: rect)

            if let text = scene.text {
                do { try drawText(text, in: cg) } catch { textError = error }
            }
        }
        if let textError { throw textError }
        return Bitmap(image.cgImage!)
    }

    private static func drawText(_ text: LogoText, in cg: CGContext) throws {
        let font = try GlyphPaths.font(named: text.fontName, size: text.pointSize)
        let attributed = NSAttributedString(string: text.string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): text.fill.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let box = GlyphPaths.typographicBox(of: line)

        cg.saveGState()
        // Draw true geometry: by default Core Graphics snaps glyph origins to the
        // pixel grid (a screen-legibility optimisation), which moved the reference
        // text by ~0.5–0.8 px while shapes and strokes matched exactly.
        cg.setAllowsFontSubpixelPositioning(true)
        cg.setShouldSubpixelPositionFonts(true)
        cg.setAllowsFontSubpixelQuantization(false)
        cg.setShouldSubpixelQuantizeFonts(false)
        cg.concatenate(GlyphPaths.lineToCanvasTransform(box: box, center: text.center, rotation: text.rotation))
        cg.textMatrix = .identity
        cg.textPosition = .zero
        CTLineDraw(line, cg)
        cg.restoreGState()
    }
}

// MARK: - SVG render (WebKit)

/// Renders an SVG string with WKWebView at exactly 1 SVG unit per device pixel,
/// so the 1024-unit canvas becomes a 1024×1024 snapshot with no resampling.
/// The web view and the `<svg>` element are `1024 / screenScale` points (CSS px)
/// wide; WebKit rasterises at screen scale, giving 1024 device pixels.
/// (`pageZoom` was tried first and was ignored, giving a 2× render.)
@MainActor
final class SVGWebRenderer: NSObject, WKNavigationDelegate {
    enum Failure: Error { case noWindowScene, noImage, navigation(Error) }

    private var loaded: CheckedContinuation<Void, Error>?

    /// The raw snapshot before normalising, for the harness calibration test.
    private(set) var lastSnapshotPixelSize: CGSize = .zero

    func render(svg: String) async throws -> Bitmap {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first
        else { throw Failure.noWindowScene }

        let screenScale = scene.traitCollection.displayScale
        let pointSide = CGFloat(GateConfig.renderSide) / screenScale

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: pointSide, height: pointSide)
        window.isHidden = false
        defer { window.isHidden = true }

        let webView = WKWebView(frame: window.bounds, configuration: WKWebViewConfiguration())
        webView.isOpaque = true
        webView.backgroundColor = .white
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = self
        window.addSubview(webView)
        defer { webView.removeFromSuperview() }

        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html,body{margin:0;padding:0;background:white;overflow:hidden}
        svg{display:block;width:\(pointSide)px;height:\(pointSide)px}</style>
        </head><body>\(svg)</body></html>
        """
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }

        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: pointSide, height: pointSide)
        configuration.snapshotWidth = NSNumber(value: Double(pointSide))
        configuration.afterScreenUpdates = true
        let snapshot = try await webView.takeSnapshot(configuration: configuration)
        guard let cgImage = snapshot.cgImage else { throw Failure.noImage }
        lastSnapshotPixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        return Bitmap(cgImage)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: Failure.navigation(error))
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: Failure.navigation(error))
        loaded = nil
    }
}
