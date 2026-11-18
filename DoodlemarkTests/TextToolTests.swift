import CoreText
import PencilKit
import XCTest
@testable import Doodlemark

/// Step 5c: the bundled logo fonts, blocked characters, tracking and ALL CAPS,
/// typing sessions, editing the text with the shape code, and text in the SVG.
@MainActor
final class TextToolTests: XCTestCase {
    private func text(_ string: String, font: String = Fixtures.logoFont, tracking: CGFloat = 0,
                      allCaps: Bool = false) -> LogoText {
        LogoText(string: string, fontName: font, center: CGPoint(x: 512, y: 512), pointSize: 120,
                 rotation: 0, fill: .second, tracking: tracking, allCaps: allCaps)
    }

    private func textModel() -> CanvasModel {
        let model = CanvasModel(project: .blank())
        model.select(.text)
        return model
    }

    // MARK: Bundled fonts

    func testEveryBundledFontLoadsByNameAndRendersPizzaRocket() throws {
        XCTAssertEqual(LogoFonts.all.count, 5)
        XCTAssertEqual(LogoFonts.all.first?.postScriptName, "LilitaOne", "the gate font is in the set")
        let registered = Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String] ?? []
        var outlines: Set<String> = []
        for font in LogoFonts.all {
            let ctFont = try GlyphPaths.font(named: font.postScriptName, size: 120)
            XCTAssertNil(CTFontCopyVariationAxes(ctFont), "\(font.displayName) is a static font")

            // Registered, and its license is bundled next to it and says OFL.
            let file = try XCTUnwrap(registered.first { CTFontCopyPostScriptName(ctFont) as String == postScriptName(ofFile: $0) },
                                     "\(font.displayName) is in UIAppFonts")
            let family = String(file.prefix { $0 != "-" })
            let license = try XCTUnwrap(Bundle.main.url(forResource: "\(family)-OFL", withExtension: "txt"),
                                        "\(family)-OFL.txt is bundled")
            XCTAssertTrue(try String(contentsOf: license, encoding: .utf8).contains("SIL OPEN FONT LICENSE Version 1.1"))

            let rocket = text("Pizza Rocket", font: font.postScriptName)
            XCTAssertTrue(LogoFonts.missingCharacters(in: rocket.string, fontName: font.postScriptName).isEmpty)
            let bounds = try GlyphPaths.path(for: rocket).boundingBoxOfPath
            XCTAssertGreaterThan(bounds.width, 400, font.displayName)
            XCTAssertGreaterThan(bounds.width, bounds.height * 3, "\(font.displayName): one line")
            outlines.insert(SVGExporter.pathData(try GlyphPaths.path(for: rocket)))
        }
        XCTAssertEqual(outlines.count, 5, "five different looks")
    }

    private func postScriptName(ofFile file: String) -> String? {
        guard let url = Bundle.main.url(forResource: file, withExtension: nil),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return nil }
        return CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
    }

    // MARK: Blocked characters

    func testCharactersAFontCantDrawAreFound() {
        for font in LogoFonts.all {
            let name = font.postScriptName
            XCTAssertEqual(LogoFonts.missingCharacters(in: "Pizza 😀 🍕", fontName: name), ["😀", "🍕"], name)
            XCTAssertEqual(LogoFonts.missingCharacters(in: "汉 Pizza", fontName: name), ["汉"], "\(name) is Latin-only")
            XCTAssertEqual(LogoFonts.missingCharacters(in: "Café ñ", fontName: name), [], "\(name) has accents")
        }
        XCTAssertEqual(LogoFonts.missingCharacters(in: "Kő", fontName: "LilitaOne"), ["ő"])
        XCTAssertEqual(LogoFonts.missingCharacters(in: "Kő", fontName: "Bungee-Regular"), [])
        XCTAssertEqual(LogoFonts.missingCharacters(in: "Hi", fontName: "Helvetica"), ["H", "i"], "not a logo font")
    }

    func testTypingABlockedCharacterKeepsTheRestAndSaysWhy() {
        let model = textModel()
        XCTAssertEqual(model.typeText("Pizza😀"), "Pizza")
        XCTAssertEqual(model.project.text?.string, "Pizza")
        XCTAssertEqual(model.textMessage, "This font can't draw \u{201C}😀\u{201D}.")
        model.typeText("Pizza")                     // the field taking back the 😀
        XCTAssertEqual(model.textMessage, "This font can't draw \u{201C}😀\u{201D}.", "the note stays")
        XCTAssertEqual(model.typeText("Pizza 汉堡"), "Pizza ")
        XCTAssertEqual(model.textMessage, "This font can't draw \u{201C}汉\u{201D} and \u{201C}堡\u{201D}.")
        XCTAssertEqual(model.typeText("Pizza R"), "Pizza R")
        XCTAssertNil(model.textMessage, "the note goes away once typing works again")
    }

    func testAtMostTwentyFourCharacters() {
        let model = textModel()
        let long = String(repeating: "Ab", count: 15)
        XCTAssertEqual(model.typeText(long), String(long.prefix(24)))
        XCTAssertEqual(model.textMessage, "Up to 24 letters and spaces.")
    }

    func testGlyphPathsRefusesAFallbackFont() {
        XCTAssertThrowsError(try GlyphPaths.path(for: text("Hi😀"))) { error in
            XCTAssertEqual(error as? GlyphPaths.Failure, .missingGlyphs("😀"))
        }
        XCTAssertThrowsError(try SVGExporter.svg(project: { var p = Project.blank(); p.text = text("Hi😀"); return p }(),
                                                  ink: PKDrawing()), "never exported with a system font")
    }

    func testSwitchingToAFontThatCantDrawTheTextIsRefused() {
        let model = textModel()
        model.setTextFont(LogoFonts.font(named: "Bungee-Regular")!)
        model.typeText("Kő")
        model.endTyping()
        model.setTextFont(LogoFonts.font(named: "LilitaOne")!)
        XCTAssertEqual(model.project.text?.fontName, "Bungee-Regular")
        XCTAssertEqual(model.textMessage, "Lilita One can't draw \u{201C}ő\u{201D}. Change the text first.")
        model.setTextFont(LogoFonts.font(named: "Poppins-ExtraBold")!)
        XCTAssertEqual(model.project.text?.fontName, "Poppins-ExtraBold")
        XCTAssertNil(model.textMessage)
    }

    // MARK: Tracking and ALL CAPS

    func testTrackingSpreadsTheLettersAroundTheCentre() throws {
        let plain = try GlyphPaths.path(for: text("Pizza")).boundingBoxOfPath
        let spaced = try GlyphPaths.path(for: text("Pizza", tracking: 200)).boundingBoxOfPath
        let kern = 200.0 / 1000 * 120                             // 24 pt after each of the first 4 letters
        XCTAssertEqual(spaced.width - plain.width, 4 * kern, accuracy: 0.01)
        XCTAssertEqual(spaced.midX, plain.midX, accuracy: 0.01, "no gap after the last letter, so still centred")
        XCTAssertEqual(spaced.height, plain.height, accuracy: 0.01)

        let tight = try GlyphPaths.path(for: text("Pizza", tracking: -50)).boundingBoxOfPath
        XCTAssertEqual(plain.width - tight.width, 4 * 6, accuracy: 0.01)

        // A single letter has nothing to space: its outline doesn't change.
        XCTAssertEqual(SVGExporter.pathData(try GlyphPaths.path(for: text("P", tracking: 300))),
                       SVGExporter.pathData(try GlyphPaths.path(for: text("P"))))
    }

    func testAllCapsDrawsCapitalsButKeepsWhatWasTyped() throws {
        let caps = text("Pizza rocket", allCaps: true)
        XCTAssertEqual(caps.string, "Pizza rocket")
        XCTAssertEqual(caps.displayString, "PIZZA ROCKET")
        XCTAssertEqual(SVGExporter.pathData(try GlyphPaths.path(for: caps)),
                       SVGExporter.pathData(try GlyphPaths.path(for: text("PIZZA ROCKET"))))
        XCTAssertNotEqual(SVGExporter.pathData(try GlyphPaths.path(for: caps)),
                          SVGExporter.pathData(try GlyphPaths.path(for: text("Pizza rocket"))))

        let model = textModel()
        model.typeText("Pizza")
        model.setTextAllCaps(true)
        XCTAssertEqual(model.project.text?.displayString, "PIZZA")
        XCTAssertEqual(model.history.undoStack.count, 2, "typing, then caps")
    }

    // MARK: Undo

    func testOneUndoStepPerTypingSession() {
        let model = textModel()
        model.chooseSlot(.third)
        for prefix in ["P", "Pi", "Piz", "Pizz", "Pizza", "Pizza ", "Pizza R", "Pizza Rocket"] { model.typeText(prefix) }
        model.endTyping()
        let text = model.project.text
        XCTAssertEqual(text?.string, "Pizza Rocket")
        XCTAssertEqual(text?.center, CGPoint(x: 512, y: 512), "centred")
        XCTAssertEqual(text?.fill, .third, "in the current color")
        XCTAssertEqual(text?.fontName, "LilitaOne")
        XCTAssertEqual(model.history.undoStack.count, 1, "eight keystrokes, one step")

        model.typeText("Pizza Rocket C")
        model.typeText("Pizza Rocket Co")
        model.endTyping()
        XCTAssertEqual(model.history.undoStack.count, 2)
        model.undo()
        XCTAssertEqual(model.project.text?.string, "Pizza Rocket")
        model.undo()
        XCTAssertNil(model.project.text)
        model.redo()
        XCTAssertEqual(model.project.text?.string, "Pizza Rocket")
    }

    func testUndoInTheMiddleOfTypingUndoesTheWholeSession() {
        let model = textModel()
        model.typeText("Pizza")                        // the very first session, not recorded yet
        XCTAssertTrue(model.canUndo, "the Undo button works while typing")
        model.endTyping()
        model.undo()
        XCTAssertTrue(model.canRedo)
        model.typeText("Pi")
        XCTAssertFalse(model.canRedo, "typing again drops the redo step")
        model.endTyping()
        model.typeText("Pizza Ro")                     // still typing
        model.undo()
        XCTAssertEqual(model.project.text?.string, "Pi")
    }

    func testErasingEveryLetterRemovesTheText() {
        let model = textModel()
        model.typeText("Hi")
        model.endTyping()
        model.typeText("H")
        model.typeText("")
        model.endTyping()
        XCTAssertNil(model.project.text)
        XCTAssertEqual(model.history.undoStack.count, 2)
    }

    func testEachTextControlIsOneStepAndASliderDragIsOne() {
        let model = textModel()
        model.typeText("Pizza")
        model.endTyping()
        model.setTextFont(LogoFonts.all[2])
        model.setTextAllCaps(true)
        model.chooseSlot(.first)
        XCTAssertEqual(model.project.text?.fill, .first, "a swatch fills the text")
        XCTAssertEqual(model.history.undoStack.count, 4)

        model.beginEdit()                              // Size slider drag
        for size in stride(from: 120.0, through: 200, by: 10) { model.setTextSize(size) }
        model.endEdit()
        model.beginEdit()                              // Letter spacing slider drag
        for tracking in stride(from: 0.0, through: 150, by: 25) { model.setTextTracking(tracking) }
        model.endEdit()
        XCTAssertEqual(model.project.text?.pointSize, 200)
        XCTAssertEqual(model.project.text?.tracking, 150)
        XCTAssertEqual(model.history.undoStack.count, 6)

        model.deleteText()
        XCTAssertNil(model.project.text)
        model.undo()
        XCTAssertEqual(model.project.text?.tracking, 150)
    }

    // MARK: Editing the text with the shape code

    func testTextMovesResizesAndTurnsLikeAShapeOneStepPerGesture() throws {
        let model = textModel()
        model.typeText("Pizza")
        model.endTyping()
        guard case .text(let start)? = model.pickedItem else { return XCTFail("the text is picked") }

        let outline = try GlyphPaths.path(for: start).boundingBoxOfPath
        XCTAssertEqual(model.stackConfig.selection, outline, "handles sit on the real outline")
        XCTAssertEqual(PickedItem.text(start).handles[2], CGPoint(x: outline.maxX, y: outline.maxY))

        model.beginEdit()
        let moved = PickedItem.text(start).moved(by: CGPoint(x: 150, y: 200), snapDistance: 0).item
        model.updateItem(moved)
        model.endEdit()
        model.beginEdit()
        let corner = PickedItem.text(model.project.text!).handles[2]
        let center = model.project.text!.center
        let bigger = PickedItem.text(model.project.text!)
            .scaled(handle: corner, finger: CGPoint(x: center.x + (corner.x - center.x) * 1.5,
                                                    y: center.y + (corner.y - center.y) * 1.5))
        model.updateItem(bigger)
        model.endEdit()
        model.beginEdit()
        model.updateItem(PickedItem.text(model.project.text!).transformed(translation: .zero, scale: 1,
                                                                          rotation: 0.4, snapDistance: 0).item)
        model.endEdit()

        XCTAssertEqual(model.project.text?.center, CGPoint(x: 662, y: 712))
        XCTAssertEqual(model.project.text!.pointSize, 180, accuracy: 0.001)
        XCTAssertEqual(model.project.text!.rotation, 30 * .pi / 180, accuracy: 1e-9, "15° steps")
        XCTAssertEqual(model.history.undoStack.count, 4, "typing + three gestures")
        model.undo()
        XCTAssertEqual(model.project.text?.rotation, 0)
        XCTAssertEqual(model.project.text!.pointSize, 180, accuracy: 0.001)
    }

    /// The handles sit just outside the outline bounds, at any zoom, so they
    /// never cover the first or last letter.
    func testHandlesClearTheOutline() throws {
        let bounds = try GlyphPaths.path(for: text("Pizza")).boundingBoxOfPath
        for zoom in [0.3, 0.6, 1, 2.5] as [CGFloat] {
            let viewport = CanvasViewport(zoom: zoom, offset: CGPoint(x: 40, y: -20))
            let a = viewport.toView(bounds.origin), b = viewport.toView(CGPoint(x: bounds.maxX, y: bounds.maxY))
            let onScreen = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
            let r = ShapeSelectionView.handleDiameter / 2
            let roomy = CGRect(x: -2000, y: -2000, width: 6000, height: 6000)
            for handle in ShapeSelectionView.handlePoints(around: bounds, viewport: viewport, visible: roomy) {
                let dot = CGRect(x: handle.x - r, y: handle.y - r, width: 2 * r, height: 2 * r)
                XCTAssertFalse(dot.intersects(onScreen.insetBy(dx: 1, dy: 1)), "zoom \(zoom)")
                XCTAssertLessThan(hypot(handle.x - onScreen.midX, handle.y - onScreen.midY),
                                  hypot(onScreen.width, onScreen.height) / 2 + 25, "still at the corner")
            }
        }
    }

    /// At the canvas edge the handles stay whole inside the canvas view
    /// (it clips), so they can still be seen and grabbed.
    func testHandlesStayInsideTheCanvasView() {
        let viewport = CanvasViewport(zoom: 0.5, offset: .zero)
        let visible = CGRect(x: 0, y: 0, width: 512, height: 512)
        let wide = CGRect(x: 2, y: 400, width: 1020, height: 120)          // wall to wall
        let r = ShapeSelectionView.handleDiameter / 2
        let points = ShapeSelectionView.handlePoints(around: wide, viewport: viewport, visible: visible)
        for p in points {
            XCTAssertTrue(visible.insetBy(dx: r - 0.001, dy: r - 0.001).contains(p), "\(p)")
        }
        XCTAssertEqual(points[0].y, 200 - ShapeSelectionView.handleOutset, "only pulled in where it has to be")
    }

    func testTextSnapsByItsOutlineBoundsAndKeepsItsSize() {
        var start = text("Pizza")
        start.center = CGPoint(x: 300, y: 300)
        let bounds = ShapeEditing.bounds(of: start)
        let toCentre = CGPoint(x: 512 - bounds.midX + 4, y: 512 - bounds.midY - 5)
        let result = ShapeEditing.moved(start, by: toCentre, snapDistance: 10)
        XCTAssertEqual(ShapeEditing.bounds(of: result.shape).midX, 512, accuracy: 1e-6)
        XCTAssertEqual(ShapeEditing.bounds(of: result.shape).midY, 512, accuracy: 1e-6)
        XCTAssertEqual(result.guides, SnapGuides(vertical: true, horizontal: true))
        XCTAssertEqual(ShapeEditing.resized(start, by: 100).pointSize, LogoText.scaleRange.upperBound)
    }

    func testOnlyTheTextToolPicksTheText() {
        let model = textModel()
        XCTAssertNil(model.pickedItem, "nothing typed yet")
        model.typeText("Hi")
        XCTAssertNotNil(model.pickedItem)
        model.select(.ink)
        XCTAssertNil(model.pickedItem)
        XCTAssertNil(model.stackConfig.selection)
    }

    // MARK: SVG

    func testTextInTheSVGIsPathsOnly() throws {
        let model = textModel()
        model.setTextFont(LogoFonts.font(named: "Pacifico-Regular")!)
        model.typeText("Pizza Rocket")
        model.setTextTracking(80)
        model.setTextAllCaps(true)
        let svg = try SVGExporter.svg(project: model.project, ink: model.ink)
        let text = try XCTUnwrap(model.project.text)
        XCTAssertTrue(svg.contains(#"  <g id="text">"# + "\n" + #"    <path fill="\#(model.project.color(for: text.fill).hexString)" d="\#(SVGExporter.pathData(try GlyphPaths.path(for: text)))"/>"#))
        for leak in ["<text", "font", "Pacifico", "Pizza", "ROCKET", "tspan"] {
            XCTAssertFalse(svg.contains(leak), "no \(leak) in the SVG: the file mustn't need the font")
        }
    }
}
