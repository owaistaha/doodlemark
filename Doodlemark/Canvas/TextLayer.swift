import SwiftUI

/// The Text layer in 1024 canvas space: the logo name as glyph outlines from
/// `GlyphPaths`, exactly what the SVG gets. Editing text is step 5.
struct TextLayer: View {
    let model: CanvasModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let text = model.project.text, let outline = try? GlyphPaths.path(for: text) {
                Path(outline).fill(Color(cgColor: text.fill.cgColor))
            }
        }
        .frame(width: CanvasViewport.canvasSide, height: CanvasViewport.canvasSide)
        .ignoresSafeArea()
    }
}
