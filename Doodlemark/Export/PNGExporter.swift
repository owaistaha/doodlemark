import PencilKit
import UIKit

/// Draws a logo the way it's exported: Shapes, then Ink, then Text, on a
/// transparent square. The Sketch layer is never in it (CLAUDE.md).
/// Gallery thumbnails use it now; the share-sheet PNG (step 7) will too.
enum PNGExporter {
    /// The logo at `pixelSide` × `pixelSide` pixels, transparent background.
    @MainActor
    static func image(project: Project, ink: PKDrawing, pixelSide: Int) -> UIImage {
        renderer(pixelSide: pixelSide).image { context in
            draw(project: project, ink: ink, in: context.cgContext, pixelSide: pixelSide)
        }
    }

    @MainActor
    static func pngData(project: Project, ink: PKDrawing, pixelSide: Int) -> Data? {
        image(project: project, ink: ink, pixelSide: pixelSide).pngData()
    }

    /// Exactly `pixelSide` pixels (scale 1), with alpha.
    static func renderer(pixelSide: Int) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard               // sRGB, like the SVG
        return UIGraphicsImageRenderer(size: CGSize(width: pixelSide, height: pixelSide), format: format)
    }

    /// Draws into a context whose drawing area is `pixelSide` pixels square.
    @MainActor
    static func draw(project: Project, ink: PKDrawing, in cg: CGContext, pixelSide: Int) {
        let side = CanvasViewport.canvasSide
        let scale = CGFloat(pixelSide) / side
        cg.saveGState()
        cg.scaleBy(x: scale, y: scale)                  // canvas space from here on

        for shape in project.shapes {
            cg.addPath(ShapeGeometry.path(for: shape))
            cg.setFillColor(project.color(for: shape.fill).cgColor)
            cg.fillPath()
        }

        drawDrawing(ink, in: cg, scale: scale)

        // GlyphPaths refuses text a font can't draw (it never gets into a
        // project): such text is left out rather than drawn in a system font.
        if let text = project.text, let outline = try? GlyphPaths.path(for: text) {
            cg.addPath(outline)
            cg.setFillColor(project.color(for: text.fill).cgColor)
            cg.fillPath()
        }
        cg.restoreGState()
    }

    /// PencilKit's own render of a drawing (what the canvas shows), in light
    /// appearance so colors are never inverted. `cg` is in canvas space.
    @MainActor
    static func drawDrawing(_ drawing: PKDrawing, in cg: CGContext, scale: CGFloat, alpha: CGFloat = 1) {
        guard !drawing.strokes.isEmpty else { return }
        let canvas = CGRect(x: 0, y: 0, width: CanvasViewport.canvasSide, height: CanvasViewport.canvasSide)
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: canvas, scale: scale)
        }
        UIGraphicsPushContext(cg)
        image.draw(in: canvas, blendMode: .normal, alpha: alpha)
        UIGraphicsPopContext()
    }
}

/// Gallery thumbnails: 512 px, like the export. A project that only has a
/// sketch so far shows the sketch, faded, so its card isn't blank.
enum Thumbnail {
    static let pixelSide = 512
    static let sketchAlpha: CGFloat = 0.6

    static func showsOnlySketch(project: Project, sketch: PKDrawing, ink: PKDrawing) -> Bool {
        project.shapes.isEmpty && project.text == nil && ink.strokes.isEmpty && !sketch.strokes.isEmpty
    }

    @MainActor
    static func image(project: Project, sketch: PKDrawing, ink: PKDrawing) -> UIImage {
        PNGExporter.renderer(pixelSide: pixelSide).image { context in
            let cg = context.cgContext
            if showsOnlySketch(project: project, sketch: sketch, ink: ink) {
                let scale = CGFloat(pixelSide) / CanvasViewport.canvasSide
                cg.saveGState()
                cg.scaleBy(x: scale, y: scale)
                PNGExporter.drawDrawing(sketch, in: cg, scale: scale, alpha: sketchAlpha)
                cg.restoreGState()
            } else {
                PNGExporter.draw(project: project, ink: ink, in: cg, pixelSide: pixelSide)
            }
        }
    }

    @MainActor
    static func pngData(project: Project, sketch: PKDrawing, ink: PKDrawing) -> Data? {
        image(project: project, sketch: sketch, ink: ink).pngData()
    }
}
