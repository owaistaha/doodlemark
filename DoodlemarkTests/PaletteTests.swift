import PencilKit
import XCTest
@testable import Doodlemark

/// Step 5a: curated palettes, palette slots, "Try another" and changing a
/// color everywhere (shapes, text and Ink lines), with undo and export.
@MainActor
final class PaletteTests: XCTestCase {

    // MARK: Curated set

    func testTwelveCuratedPalettesOfThreeDistinctColors() {
        XCTAssertEqual(Palettes.curated.count, 12)
        XCTAssertEqual(Set(Palettes.curated.map(\.name)).count, 12, "names are unique")
        XCTAssertEqual(Set(Palettes.curated.map(\.colors)).count, 12, "no palette twice")
        for palette in Palettes.curated {
            XCTAssertEqual(palette.colors.count, 3, palette.name)
            XCTAssertEqual(Set(palette.colors).count, 3, palette.name)
        }
        XCTAssertEqual(Palettes.starter, [Fixtures.tangerine, Fixtures.ink, Fixtures.butter],
                       "the starter is the Doodlemark look")
    }

    /// The rules in `Palettes`' doc comment, so a palette added later can't
    /// break them.
    func testEveryCuratedPaletteHasEnoughContrast() {
        let white = HexColor(red: 255, green: 255, blue: 255)
        for palette in Palettes.curated {
            let c = palette.colors
            let dark = c[PaletteSlot.second.rawValue]
            XCTAssertEqual(c.min { luminance($0) < luminance($1) }, dark, "\(palette.name): second color is the darkest")
            for other in [c[0], c[2]] {
                XCTAssertGreaterThanOrEqual(contrast(dark, other), 3, "\(palette.name): dark vs \(other.hexString)")
            }
            for i in 0..<3 {
                for j in (i + 1)..<3 {
                    XCTAssertGreaterThanOrEqual(deltaE(c[i], c[j]), 25,
                                                "\(palette.name): \(c[i].hexString) vs \(c[j].hexString)")
                }
                XCTAssertGreaterThanOrEqual(contrast(c[i], white), 1.4, "\(palette.name): \(c[i].hexString) on white")
            }
        }
    }

    func testTryAnotherCyclesThroughEveryPaletteAndWraps() {
        let model = CanvasModel(project: .blank())
        var seen = [model.project.palette]
        for _ in 1..<Palettes.curated.count {
            model.tryAnotherPalette()
            seen.append(model.project.palette)
        }
        XCTAssertEqual(seen, Palettes.curated.map(\.colors), "in order, starting from the starter")
        model.tryAnotherPalette()
        XCTAssertEqual(model.project.palette, Palettes.starter, "wraps around")
    }

    func testTryAnotherAfterAnEditedColorGoesOnFromTheLastPalette() {
        let model = CanvasModel(project: .blank())
        model.tryAnotherPalette()                                   // Ocean
        model.beginColorEdit(.first)
        model.previewColor(HexColor("#123456")!)
        model.endColorEdit()
        model.tryAnotherPalette()
        XCTAssertEqual(model.project.palette, Palettes.curated[2].colors, "Jungle comes after Ocean")
    }

    // MARK: Slots

    func testFillIsStoredAsASlotNumber() throws {
        let shape = LogoShape(id: UUID(), kind: .circle, center: .zero, size: 10, rotation: 0, fill: .third)
        let json = try XCTUnwrap(String(data: ProjectCoding.makeEncoder().encode(shape), encoding: .utf8))
        XCTAssertTrue(json.contains(#""fill" : 2"#), json)
        XCTAssertFalse(json.contains("#"), "no hex in a shape")
    }

    func testTapOnASwatchMakesItThePenColor() {
        let model = CanvasModel(project: .blank())
        XCTAssertEqual(model.currentSlot, .second, "dark by default")
        XCTAssertEqual(model.penColor, Fixtures.ink)
        model.chooseSlot(.third)
        XCTAssertEqual(model.penColor, Fixtures.butter)
        XCTAssertEqual(model.stackConfig.inkColor, Fixtures.butter, "the Ink canvas gets it")
        XCTAssertFalse(model.canUndo, "choosing a color isn't an edit")
    }

    // MARK: Changing a color everywhere

    /// A model with a shape and text in slot 1, Ink lines in slots 1 and 2,
    /// and a line in a color that isn't in the palette.
    private func coloredModel() -> CanvasModel {
        var project = Project.blank()
        project.shapes = [LogoShape(id: UUID(), kind: .circle, center: CGPoint(x: 512, y: 400),
                                    size: 300, rotation: 0, fill: .first)]
        project.text = Fixtures.pizzaText()
        project.text?.fill = .first
        let model = CanvasModel(project: project)
        model.ink = PKDrawing(strokes: [
            line(y: 700, color: Fixtures.tangerine),
            line(y: 750, color: Fixtures.ink),
            line(y: 800, color: Self.offPalette),
        ])
        return model
    }

    private static let offPalette = HexColor("#00AA00")!
    private static let newColor = HexColor("#2F5BFF")!

    private func line(y: CGFloat, color: HexColor) -> PKStroke {
        Fixtures.monolineStroke([CGPoint(x: 200, y: y), CGPoint(x: 800, y: y)], color: color)
    }

    private func inkColors(_ model: CanvasModel) -> [HexColor] {
        model.ink.strokes.map { SVGExporter.inkColor($0.ink.color).color }
    }

    func testRecolorUpdatesShapesInkAndText() {
        let model = coloredModel()
        model.beginColorEdit(.first)
        model.previewColor(HexColor("#FFFF00")!)    // the picker passes through a few colors
        model.previewColor(Fixtures.ink)           // …including another slot's color
        model.previewColor(Self.newColor)
        model.endColorEdit()

        XCTAssertEqual(model.project.palette, [Self.newColor, Fixtures.ink, Fixtures.butter])
        XCTAssertEqual(model.project.color(for: model.project.shapes[0].fill), Self.newColor, "shape")
        XCTAssertEqual(model.project.color(for: model.project.text!.fill), Self.newColor, "text")
        XCTAssertEqual(inkColors(model), [Self.newColor, Fixtures.ink, Self.offPalette],
                       "only slot 1's lines change, even after passing through slot 2's color")
        XCTAssertEqual(model.history.undoStack.count, 1, "one undo step for the whole recolor")
    }

    func testRecolorKeepsEverythingButTheColor() {
        let model = coloredModel()
        let before = model.ink.strokes[0]
        model.beginColorEdit(.first)
        model.previewColor(Self.newColor)
        model.endColorEdit()
        let after = model.ink.strokes[0]
        XCTAssertEqual(after.ink.inkType, before.ink.inkType)
        XCTAssertEqual(after.transform, before.transform)
        XCTAssertEqual(after.path.map(\.location), before.path.map(\.location))
        XCTAssertEqual(after.path.map(\.size), before.path.map(\.size))
    }

    func testUndoRestoresTheWholeRecolorAndRedoReappliesIt() throws {
        let model = coloredModel()
        let svgBefore = try SVGExporter.svg(project: model.project, ink: model.ink)
        model.beginColorEdit(.first)
        model.previewColor(Self.newColor)
        model.endColorEdit()
        let svgAfter = try SVGExporter.svg(project: model.project, ink: model.ink)
        let restores = model.restoreRequest

        model.undo()
        XCTAssertEqual(model.project.palette, Palettes.starter)
        XCTAssertEqual(inkColors(model), [Fixtures.tangerine, Fixtures.ink, Self.offPalette])
        XCTAssertEqual(try SVGExporter.svg(project: model.project, ink: model.ink), svgBefore)
        XCTAssertGreaterThan(model.restoreRequest, restores, "the Ink canvas reloads")

        model.redo()
        XCTAssertEqual(try SVGExporter.svg(project: model.project, ink: model.ink), svgAfter)
    }

    func testSVGExportUsesTheNewColors() throws {
        let model = coloredModel()
        model.beginColorEdit(.first)
        model.previewColor(Self.newColor)
        model.endColorEdit()
        let svg = try SVGExporter.svg(project: model.project, ink: model.ink)
        let new = Self.newColor.hexString
        XCTAssertTrue(svg.contains(#"<g id="shapes">"# + "\n" + #"    <path fill="\#(new)""#), "shape")
        XCTAssertTrue(svg.contains(#"<g id="text">"# + "\n" + #"    <path fill="\#(new)""#), "text")
        XCTAssertTrue(svg.contains(#"stroke="\#(new)""#), "ink")
        XCTAssertFalse(svg.contains(Fixtures.tangerine.hexString), "the old color is gone")
    }

    func testTryAnotherRecolorsInkTooInOneStep() {
        let model = coloredModel()
        model.tryAnotherPalette()
        let ocean = Palettes.curated[1].colors
        XCTAssertEqual(model.project.palette, ocean)
        XCTAssertEqual(inkColors(model), [ocean[0], ocean[1], Self.offPalette])
        XCTAssertEqual(model.history.undoStack.count, 1)
        model.undo()
        XCTAssertEqual(model.project.palette, Palettes.starter)
        XCTAssertEqual(inkColors(model), [Fixtures.tangerine, Fixtures.ink, Self.offPalette])
    }

    func testClosingThePickerWithoutAChangeIsNoUndoStep() {
        let model = coloredModel()
        model.beginColorEdit(.second)
        model.previewColor(Self.newColor)
        model.previewColor(Fixtures.ink)            // back to where it was
        model.endColorEdit()
        XCTAssertFalse(model.canUndo)
        XCTAssertNil(model.editingSlot)
    }

    func testTwoSlotsNeverShareAColorSoTheirLinesStayApart() {
        let model = coloredModel()
        model.beginColorEdit(.third)
        model.previewColor(Fixtures.tangerine)      // slot 1's color, picked for slot 3
        model.endColorEdit()
        let third = model.project.palette[2]
        XCTAssertNotEqual(third, Fixtures.tangerine, "nudged apart")
        XCTAssertLessThanOrEqual(abs(Int(third.green) - Int(Fixtures.tangerine.green)), 3, "invisibly")
        XCTAssertEqual(third.red, Fixtures.tangerine.red)
        XCTAssertEqual(third.blue, Fixtures.tangerine.blue)

        // Changing slot 3 again leaves slot 1's line alone.
        model.beginColorEdit(.third)
        model.previewColor(Self.newColor)
        model.endColorEdit()
        XCTAssertEqual(inkColors(model), [Fixtures.tangerine, Fixtures.ink, Self.offPalette])
    }

    func testInkLinksToASlotByExactColor() {
        let near = HexColor("#FE5A1F")!                       // 1/255 off tangerine
        let drawing = PKDrawing(strokes: [line(y: 100, color: Fixtures.tangerine), line(y: 200, color: near)])
        XCTAssertEqual(InkPalette.slots(of: drawing, palette: Palettes.starter), [.first, nil])
    }

    /// The nudge, for every corner of the color cube and the values next to
    /// the ends of each channel, against the worst case: one other slot with
    /// the picked color and the other with the first nudge already taken.
    func testNudgeIsAtMostThreeInOneChannelAndAlwaysDistinct() {
        let values: [UInt8] = [0, 1, 2, 3, 4, 127, 251, 252, 253, 254, 255]
        for r in values { for g in values { for b in values {
            let color = HexColor(red: r, green: g, blue: b)
            let first = InkPalette.keepingApart(color, from: [color])
            for others in [[color], [color, first], [first, color]] {
                let result = InkPalette.keepingApart(color, from: others)
                XCTAssertFalse(others.contains(result), "\(color.hexString) vs \(others.map(\.hexString))")
                XCTAssertLessThanOrEqual(channelChange(color, result), 3, color.hexString)
                XCTAssertLessThanOrEqual(channelsChanged(color, result), 1, color.hexString)
            }
        } } }
        XCTAssertEqual(InkPalette.keepingApart(Fixtures.tangerine, from: [Fixtures.ink]), Fixtures.tangerine,
                       "a color no other slot has is never nudged")
    }

    /// Through the editor: a slot given another slot's color exports within
    /// 3/255 of the picked color, for its shape, its text and its Ink line.
    func testNudgedColorInTheSVGIsWithinThreeOfThePickedColor() throws {
        let picks = ["#FF5A1F", "#000000", "#FFFFFF", "#00FF00", "#FFFEFF", "#7F7F7F"].map { HexColor($0)! }
        for picked in picks {
            for second in [Fixtures.ink, InkPalette.keepingApart(picked, from: [picked])] where second != picked {
                var project = Project.blank()
                let third = HexColor("#123456")!
                project.palette = [picked, second, third]
                project.shapes = [LogoShape(id: UUID(), kind: .circle, center: CGPoint(x: 512, y: 400),
                                            size: 300, rotation: 0, fill: .third)]
                project.text = Fixtures.pizzaText()
                project.text?.fill = .third
                let model = CanvasModel(project: project)
                model.ink = PKDrawing(strokes: [line(y: 700, color: third)])

                model.beginColorEdit(.third)
                model.previewColor(picked)                     // slot 1's color
                model.endColorEdit()

                let svg = try SVGExporter.svg(project: model.project, ink: model.ink)
                let exported = Set(svg.matches(of: /(?:fill|stroke)="(#[0-9A-F]{6})"/).map { HexColor(String($0.1))! })
                    .subtracting([second])
                XCTAssertEqual(exported.count, 1, "shape, text and line share the nudged color: \(exported)")
                let nudged = try XCTUnwrap(exported.first)
                XCTAssertEqual(nudged, model.project.palette[2])
                XCTAssertNotEqual(nudged, picked, "slots stay distinct")
                XCTAssertNotEqual(nudged, second)
                XCTAssertLessThanOrEqual(channelChange(picked, nudged), 3, "\(picked.hexString) → \(nudged.hexString)")
            }
        }
    }

    private func channelChange(_ a: HexColor, _ b: HexColor) -> Int {
        max(abs(Int(a.red) - Int(b.red)), abs(Int(a.green) - Int(b.green)), abs(Int(a.blue) - Int(b.blue)))
    }

    private func channelsChanged(_ a: HexColor, _ b: HexColor) -> Int {
        [a.red != b.red, a.green != b.green, a.blue != b.blue].filter { $0 }.count
    }

    // MARK: Colour maths (WCAG 2 relative luminance, CIE76 ΔE)

    private func linear(_ c: UInt8) -> Double {
        let v = Double(c) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private func luminance(_ c: HexColor) -> Double {
        0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    private func contrast(_ a: HexColor, _ b: HexColor) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func lab(_ c: HexColor) -> (Double, Double, Double) {
        let (r, g, b) = (linear(c.red), linear(c.green), linear(c.blue))
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    private func deltaE(_ a: HexColor, _ b: HexColor) -> Double {
        let (p, q) = (lab(a), lab(b))
        return ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) + (p.2 - q.2) * (p.2 - q.2)).squareRoot()
    }
}
