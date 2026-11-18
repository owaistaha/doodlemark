import SwiftUI

/// The Shapes layer in 1024 canvas space. Outlines come only from
/// `ShapeGeometry`, the same function the SVG exporter uses. Adding, moving
/// and resizing shapes is step 5; for now it draws what the project holds.
struct ShapesLayer: View {
    let model: CanvasModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(model.project.shapes) { shape in
                Path(ShapeGeometry.path(for: shape))
                    .fill(Color(cgColor: shape.fill.cgColor))
            }
        }
        .frame(width: CanvasViewport.canvasSide, height: CanvasViewport.canvasSide)
        .ignoresSafeArea()
    }
}
