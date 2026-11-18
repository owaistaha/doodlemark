import PencilKit
import XCTest
@testable import Doodlemark

/// Documents how thick PencilKit really draws a monoline stroke, compared with
/// `PKStrokePoint.size.width`. The exporter's `stroke-width` comes from this law
/// (`SVGExporter.renderedMonolineWidth`), so if a future iOS changes it, this
/// test fails first and says by how much.
///
/// Measured on the iPadOS 26.5 simulator:
///
/// | size.width | rendered |      | size.width | transform scale | rendered |
/// |-----------:|---------:|------|-----------:|----------------:|---------:|
/// | 1–2        | ~0       |      | 8          | 1.5             | 18       |
/// | 3          | 2        |      | 8          | 2               | 24       |
/// | 4          | 4        |      | 4          | 2               | 8        |
/// | 8          | 12       |      | 16         | 0.5             | 14       |
/// | 16         | 28       |
/// | 32         | 60       |      → rendered = max(0, 2·w − 4) × transform scale
/// | 48         | 92       |
///
/// Force, nib height, control-point spacing and render scale don't change it.
@MainActor
final class MonolineWidthTests: XCTestCase {
    /// Renders a horizontal monoline stroke at 4x and integrates alpha down one
    /// column at x = 512 (well away from the caps). The summed coverage is the
    /// line's thickness, with sub-pixel precision.
    private func renderedThickness(pointWidth: CGFloat, transformScale: CGFloat = 1) -> CGFloat {
        let transform = CGAffineTransform(translationX: 512, y: 512)
            .scaledBy(x: transformScale, y: transformScale)
            .translatedBy(x: -512, y: -512)
        let stroke = GateFixtures.stroke([CGPoint(x: 100, y: 512), CGPoint(x: 924, y: 512)],
                                         width: pointWidth, transform: transform)
        let scale: CGFloat = 4
        let rect = CGRect(x: 0, y: 312, width: 1024, height: 400)
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = PKDrawing(strokes: [stroke]).image(from: rect, scale: scale)
        }
        let cgImage = image.cgImage!
        let width = cgImage.width, height = cgImage.height

        var alpha = [UInt8](repeating: 0, count: width * height)
        alpha.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        var total = 0
        let x = Int(512 * scale)
        for y in 0..<height { total += Int(alpha[y * width + x]) }
        return CGFloat(total) / 255 / scale   // in points
    }

    func testRenderedThicknessFollowsTheMeasuredLaw() {
        for pointWidth: CGFloat in [3, 4, 6, 7.3, 8, 12, 16, 24, 32, 48] {
            let measured = renderedThickness(pointWidth: pointWidth)
            let law = SVGExporter.renderedMonolineWidth(pointWidth: pointWidth)
            print("MONOLINE| size.width \(pointWidth) → rendered \(String(format: "%.3f", measured)) pt, law \(String(format: "%.3f", law))")
            XCTAssertEqual(measured, law, accuracy: 0.05, "size.width \(pointWidth)")
        }
    }

    func testTransformScaleMultipliesTheRenderedThickness() {
        for (pointWidth, scale): (CGFloat, CGFloat) in [(8, 1.5), (8, 2), (4, 2), (16, 0.5)] {
            let measured = renderedThickness(pointWidth: pointWidth, transformScale: scale)
            let law = SVGExporter.renderedMonolineWidth(pointWidth: pointWidth) * scale
            print("MONOLINE| size.width \(pointWidth) × transform \(scale) → rendered \(String(format: "%.3f", measured)) pt, law \(String(format: "%.3f", law))")
            XCTAssertEqual(measured, law, accuracy: 0.05)
        }
    }

    func testVeryThinStrokesRenderAlmostNothing() {
        XCTAssertLessThan(renderedThickness(pointWidth: 1), 0.1)
        XCTAssertLessThan(renderedThickness(pointWidth: 2), 0.1)
        XCTAssertEqual(SVGExporter.renderedMonolineWidth(pointWidth: 2), 0)
    }
}
