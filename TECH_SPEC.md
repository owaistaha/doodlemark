# Doodlemark — Technical Spec (v1)

## Stack
- **Client:** Swift 6 / SwiftUI, native **iPadOS only**, deployment target
  iPadOS 17.0 (tested on the iPadOS 26.5 simulator; older runtimes are not
  installed). Native, not Flutter: Apple Pencil latency and palm rejection, PencilKit's tool
  picker and the stroke data model are the whole product, and Flutter has no
  first-class PencilKit equivalent.
- **Drawing:** Apple **PencilKit** (`PKCanvasView`, `PKDrawing`, `PKStroke`).
  It's free, low-latency and handles Pencil prediction and palm rejection. Two
  `PKCanvasView`s are used: one for Sketch, one for Ink.
- **Vector shapes and text:** our own Codable model rendered with SwiftUI
  `Path` / Core Graphics. Text outlines come from Core Text
  (`CTFontCreatePathForGlyph`).
- **Persistence:** plain files in the app's Documents folder (Codable JSON +
  `PKDrawing.dataRepresentation()`). No SwiftData or Core Data needed.
- **Backend / AI:** **none.** Fully offline, with no keys or secrets. That makes
  the App Store Kids category and privacy labels trivial, and the app costs €0 to run.
- **Project generation:** XcodeGen (`project.yml`). Never hand-edit `.pbxproj`.

## Input: finger, any stylus, Apple Pencil
- Both `PKCanvasView`s use `canvasView.drawingPolicy = .anyInput` by default,
  so one finger draws. **Two fingers** pan/zoom the canvas. The layer stack
  does this, not each `PKCanvasView`: one `CanvasViewport` (zoom + offset in
  1024 space) drives both canvases and the SwiftUI Shapes/Text layers, and
  only the active layer takes one-finger touches (`Canvas/PencilCanvas.swift`,
  proven by the step 4a spike, RISKS.md #4).
- Capacitive styluses (rubber/mesh tips) are seen by iPadOS as a finger, so
  `.anyInput` covers them. Logitech Crayon and Apple Pencil report as
  `.pencil` touches, and both work under `.anyInput` too.
- The "Pencil only" toggle switches to `.pencilOnly`, for Pencil users who
  rest their palm on the screen. Save it in `UserDefaults`.
- Shapes/Text layers use SwiftUI gestures that accept any touch: drag to move,
  pinch/rotate with two fingers, plus corner handles for one-finger resizing
  (a finger can't pinch a small object precisely).
- Ink is monoline, and nothing reads `force`/`altitude`, so every input
  gives the same result. That's a nice side effect of the SVG decision.
- Finger strokes are shakier than a Pencil's. Add light smoothing in the
  exporter (the RDP + curve fit already does this), and give the Ink pen a
  sensible default Line size (16), so lines look clean without pressure.

### Line size (Ink pen)
The "Line size" control shows the **drawn thickness** in 1024 canvas space,
4–40 in steps of 2, default 16. Raw PencilKit widths are never shown. Three
widths are involved (measured on the iPadOS 26.5 simulator):
- **size**: the drawn thickness, what the user sees and picks.
- **tool width**: what `PKInkingTool(.monoline, width:)` gets. Always
  `LineSize.toolWidth(forSize:)` = size / 2, never computed anywhere else.
- **stored width**: what PencilKit writes to every `PKStrokePoint.size.width`
  for a touch stroke: tool width + 2, i.e. (size + 4) / 2
  (`FingerStrokeUITests.testToolWidthToStoredWidth`). It renders 2·w − 4 thick
  (step 3 below), so size = 2·tool width.

Don't pass (size + 4) / 2 to the tool. That's the stored width, and it would
draw every line 4 px too thick. The tool → stored offset is only measured for
touch input. Pencil input is unverified (RISKS.md #9).

## Security / privacy note
No network calls at all in v1. No third-party SDKs (no analytics, crash
reporting or ads). If the app is ever listed in the Kids category, Apple
restricts third-party analytics and advertising, so starting from zero
network code is the easy path. Privacy label: "Data Not Collected".

## Riskiest assumption — test it FIRST
> **A logo drawn in PencilKit can be exported as an SVG that looks the same as
> the canvas.**

PencilKit only exports raster images (`drawing.image(from:scale:)`). There is no
SVG export, so we build it. Each `PKStroke` exposes `path: PKStrokePath` (a cubic
B-spline of `PKStrokePoint`s with `location`, `size`, `opacity`, …), plus
`transform`, `ink` (type and color) and an optional `mask`.

The design choices below make this risk small:

1. **Ink layer = `.monoline` ink only** (constant width, iPadOS 17+). A
   constant-width stroke exports as one SVG `<path>` with
   `fill="none" stroke-width=W stroke-linecap="round" stroke-linejoin="round"`.
   That's simple and almost exact. Variable-width pressure strokes would need
   outline polygons, and that's deferred.
2. **Ink layer = vector eraser only** (`PKEraserTool(.vector)`). The pixel eraser
   splits and masks strokes (`stroke.mask`), which makes SVG export much harder.
   With the vector eraser, every remaining stroke is whole.
3. **Always apply `stroke.transform`** to points before writing them.
4. **Sketch layer is never exported as vector.** It's for doodling and gets
   hidden on export.

### Stroke → SVG pipeline
1. For each stroke on the Ink layer:
   `stroke.path.interpolatedPoints(by: .distance(2))` gives a dense polyline in
   canvas space, after `stroke.transform` is applied.
2. Simplify with Ramer–Douglas–Peucker (tolerance 0.25pt; 0.5 visibly
   flattened finger wobble in the gate), then fit cubic Béziers: Catmull-Rom
   tangents, handles a third of the shorter neighbouring chord, and **corner
   detection** (turns > 45° keep one-sided tangents, or a "V" becomes a "U").
3. Width: PencilKit does **not** draw a monoline stroke `point.size.width` thick.
   Measured: rendered = max(0, 2·w − 4) × transform scale, where w = median
   `point.size.width` (4 → 4, 8 → 12, 16 → 28; w ≤ 2 draws nothing). See
   `SVGExporter.renderedMonolineWidth` and `MonolineWidthTests`. The canvas
   stores tool width + 2, so the exported `stroke-width` equals the Line size
   (see "Line size" above).
4. Color = `stroke.ink.color` → `#RRGGBB` + `stroke-opacity`.
5. Shapes → `<path>` with `fill`, generated from the same geometry
   function that draws them on screen (one source of truth).
6. Text → glyph outlines via Core Text → `<path>` with `fill`. **Never** a
   `<text>` element: the user's export target won't have the font.
7. Layer order in the SVG: Shapes, then Ink, then Text. `viewBox="0 0 1024 1024"`, with canvas space = 1024×1024 points.

### Hard gate (before any real UI)
A unit test plus a tiny debug screen:
- Build a `PKDrawing` in code (a line, a circle-ish curve, a zig-zag) plus a
  circle shape and the word "Pizza" in one bundled font.
- Export the SVG. Render it back with `WKWebView` (`takeSnapshot`) at 1024px.
  Render the canvas with `drawing.image` + shapes + text at 1024px.
- The fixture also has one stroke with a non-identity `transform` and one
  single-tap dot (exported as a zero-length segment with round caps).
- Normalise both renders to 1024×1024 px at 1x on white. Render the native
  side under an explicit light trait, so ink colors aren't adapted for dark
  mode. Convert every color to sRGB before writing hex.
- Draw the native text with `CTLineDraw`, independently of `GlyphPaths`, so
  a glyph-outline bug (flip, offset, kerning) shows up as a diff.
- Pixel-compare. Pass = < 2% of all pixels differ by more than a small
  tolerance **and** the IoU of painted pixels is above a fixed threshold
  (set in the test; only ever raised), **and** no 32×32 tile has too many
  mismatching painted pixels. Global ratios dilute a small local error (one
  short stroke in a big logo), so the tile check catches it. All thresholds live
  in `DoodlemarkTests/Gate/GateConfig.swift`, with the reasoning.
- Negative controls: the same comparison with one stroke shifted, and with
  one stroke dropped, must **fail**. This proves the gate has teeth.
- If corners round off after RDP + Catmull-Rom, add corner detection. Never
  loosen thresholds to make the test pass.
- **The human** draws on a real iPad **with a finger, then with a Pencil/stylus if available**, exports, and opens the SVG in Safari (and
  Figma if available). It must look the same.
If this fails, fix the exporter before touching gallery or mockup UI. If
monoline export can't be made faithful, that's a stop-and-rethink moment, not
something to work around in the UI.

## Learn mode

### Lesson format (bundled JSON, `Resources/Lessons/<id>.json`)
```json
{
  "id": "rocket",
  "title": "Rocket in 5 strokes",
  "level": 1,
  "palette": ["#FF5A1F", "#1C1B22", "#FFC93C"],
  "mirror": true,
  "steps": [
    {
      "tip": "Start with one simple curve. Mirror draws the other half.",
      "kind": "ink",
      "points": [[300,112],[288,130],[272,170],[262,230],[262,300]],
      "width": 14
    }
  ]
}
```
- `points` are in the 1024×1024 canvas space (the same space as projects),
  authored as polylines and resampled at load.
- `kind`: `ink` (traced with the monoline pen) or `shape` (step places a
  shape from `Models/LogoShape`, e.g. the big circle). The user still taps to
  confirm a shape step, so every step is interactive.
- `mirror: true` → the lesson turns on Mirror, and targets only cover the left half.

### Stroke scoring (pure Swift, no UI, fully unit-tested)
1. Take the user's stroke (`interpolatedPoints`, `stroke.transform`
   applied) and the target polyline. **Resample both to N = 64 points** spaced
   evenly along their length.
2. **Direction:** if the user went the opposite way, compare against the
   reversed target too and take the better match (kids won't always start at the dot).
3. **Shape distance = discrete Fréchet distance** between the two resampled
   polylines, in canvas points.
4. **Smoothness = mean absolute turning angle** between consecutive segments
   of the user's resampled stroke (it spots wobble).
5. **Length check:** user length / target length must be within 0.6–1.5, or
   it's a miss ("Try drawing the whole line").
6. Stars: Fréchet ≤ 18pt → 3★ · ≤ 36pt → 2★ · ≤ 60pt → 1★ · else 0★ (redo).
   Thresholds are in 1024 canvas space only. Strokes are read in canvas
   space, which is already zoom-independent, so never scale by `canvasZoom`.
   Drop one star if smoothness is worse than a threshold, and say so in the tip.
7. Tip text is picked from fixed copy by the main problem
   (shape / direction / length / wobble). No generated text.

Starting thresholds come from testing on a real iPad with a finger. Make them
constants in `ScoringConfig.swift`, not magic numbers.

### Lesson player
- The same canvas screen in "lesson mode": the **ghost layer** (target strokes,
  `pencilBlue` at 25% opacity, dashed) is a SwiftUI overlay above Sketch.
  Only the current step is fully visible; done steps are solid ink.
- Start dot + arrow = a small overlay at `points[0]`, pointing along the first segment.
- On `canvasViewDrawingDidChange` with a new stroke on Ink → score it →
  show the result card. **Redo** removes that stroke; **Next** keeps it.
- Tools other than Ink are hidden in lesson mode (fewer ways to get lost).

### Progress
`Documents/learn.json`: `{ "<lessonId>": { "bestStars": 12, "maxStars": 15, "completedAt": "…" } }`.
Written atomically, like projects.

### "Make it yours"
Create a new `Project` named after the lesson, with the lesson palette and
`symmetryOn = lesson.mirror`. Ink = the user's kept strokes as a `PKDrawing`
(mirrored copies included), Shapes = the lesson's shape steps. Then open it in
normal editing mode.

## Data model (files, no database)
```
Documents/Projects/<uuid>/
  project.json      // ProjectMeta + shapes + text + palette
  sketch.drawing    // PKDrawing.dataRepresentation()
  ink.drawing       // PKDrawing.dataRepresentation()
  thumb.png         // 512px gallery thumbnail, regenerated on save
```

```swift
struct Project: Codable, Identifiable {
  var id: UUID
  var name: String            // defaults to the prompt or "Untitled logo"
  var createdAt: Date
  var updatedAt: Date
  var palette: [HexColor]     // exactly 3
  var shapes: [LogoShape]
  var text: LogoText?
  var symmetryOn: Bool
  var gridOn: Bool
}

struct LogoShape: Codable, Identifiable {
  var id: UUID
  var kind: Kind              // .circle, .roundedSquare, .triangle, .star
  var center: CGPoint         // canvas space (0...1024)
  var size: CGFloat
  var rotation: Double        // radians
  var fill: PaletteSlot       // 0/1/2, never a hex (see "Palette")
}

struct LogoText: Codable {
  var string: String
  var fontName: String        // must be one of the bundled OFL fonts
  var center: CGPoint
  var pointSize: CGFloat
  var rotation: Double
  var fill: PaletteSlot       // 0/1/2
}
```
**Shape bounds (step 5):** selection handles, hit-testing and snapping use the
shape's real path bounds (`ShapeGeometry.path(for:).boundingBoxOfPath`), never
the `size × size` box. A regular star is narrower than its box.

Saving: debounce 1s after any change, write atomically (`.atomic`). Never
write all three files on every stroke.

## Palette
- 12 curated 3-color palettes in `Models/Palettes.swift`. Rules, checked by
  `PaletteTests`: the second color is the darkest (the default Ink pen draws
  dark lines whatever the palette) with ≥ 3:1 contrast against the other two
  (WCAG's minimum for graphics); the three colors are clearly different
  (CIE76 ΔE ≥ 25); each shows on the white canvas (≥ 1.4:1 against white).
- Shapes and text store a **palette slot** (0/1/2), never a hex. The screen
  and the exporter resolve it through `project.palette`, so changing a
  slot's color recolors everything that uses it.
- Ink strokes are PencilKit strokes and only know a color. A stroke belongs
  to the slot whose color it has (± 1 per sRGB channel; the pen only draws
  palette colors), and a slot change rewrites `stroke.ink.color` for that
  slot's strokes (`Canvas/InkPalette.swift`). Ink type, points, widths and
  transform don't change. Lines in a color that isn't in the palette stay
  as they are. So that slots can always be told apart, a slot never gets a
  color within matching distance of another slot: it's nudged by 3 in green.
- Tap a swatch = current color (Ink pen, new shapes). "Try another" = the next curated palette. Tap and hold = the system
  color picker (`UIColorPickerViewController`, a popover from UIKit, because
  SwiftUI's `ColorPicker` only opens from its own color well). Every color it
  shows applies live; closing it makes the whole change one undo step (none
  if the color ended up the same). Slot strokes are taken from the drawing as
  it was when the picker opened, so passing through another slot's color
  never merges two slots' lines.
- The undo snapshot includes the palette.

## Undo history
One history for all four layers (`Canvas/CanvasHistory.swift`): every user
change records a snapshot of the state *before* it (Sketch drawing, Ink
drawing, shapes, text, palette). Undo/redo swap snapshots and the canvases reload.
- PencilKit's own undo is off on both canvases: they return a
  `HistoryUndoManager` whose registration is disabled. (PencilKit's undo
  can't undo a programmatically appended mirror copy; step 4a spike, RISKS #1.)
- Top-bar Undo/Redo buttons; ⌘Z / ⇧⌘Z are the scene's Edit-menu commands
  (`CanvasCommands` replaces the system Undo/Redo items). Two-finger tap = undo,
  three-finger tap = redo; both taps wait for pan and pinch to fail, so a
  pinch never undoes. The system undo/redo gestures and the Edit menu reach
  the same history through `HistoryUndoManager` (the stack is first responder).
- One tool use is one step: everything between `canvasViewDidBeginUsingTool`
  and `…DidEndUsingTool` (e.g. one eraser drag across several lines).
- Capped at 100 steps (`CanvasHistory.limit`). Snapshots share unchanged
  strokes: 100 steps on a busy drawing (500 strokes, 75,000 points, 0.92 MB
  serialized) add about 6.5 MB, against about 92 MB if every snapshot were a
  full copy (`HistoryMemoryTests`).

## Smooth my lines (Ink only, default on)
When an Ink stroke ends it is replaced by a smoothed copy in the same undo
step (`Canvas/StrokeSmoother.swift`): a Gaussian along the stroke (σ = 5 pt),
run between pinned points with odd reflection at each one, so straight runs
don't move and nothing slides off a corner. Pinned: both endpoints and every
corner sharper than 45°, found with the exporter's corner test on a 2 pt RDP
simplification (coarse enough that finger wobble isn't a corner). Dots are
untouched; only point locations change.
**Learn mode scores the RAW stroke, before smoothing.** Smoothing would hide
exactly the wobble the score and tips are about.

## Mirror (Ink only)
Vertical axis at x = 512. When an Ink stroke ends (after smoothing), a copy
with a horizontal flip in its `transform` is appended (`Canvas/Symmetry.swift`).
Points and widths are untouched and the exporter applies transforms, so the
copy exports exactly (gate case `smoothed-mirrored`). The stroke, its smoothing
and its mirror copy are one undo step because the history snapshots the whole
canvas. On screen: a dashed `pencilBlue` axis line and the hint pill "Mirror
is on: draw one side, the other side copies you".

## Grid
A 10 × 10 grid over the canvas (one line on the mirror axis), drawn in view
space under the Sketch layer so lines stay 1 pt at any zoom. Grid and the
mirror axis are on screen only: never in the SVG or PNG.

## Testing & CI (CV quality)
- XCTest targets: `StrokeScorerTests` (identical stroke = 3★, reversed
  stroke = same score, shifted 50pt = lower, half-length = miss, zig-zag over a
  straight target = wobble tip), `LessonLoaderTests` (every bundled lesson
  parses and its points are inside 0…1024), `SVGExportTests` (pixel-diff gate), `ShapeGeometryTests`,
  `SymmetryTests`, `ProjectStoreTests` (save → load round-trip, atomic write).
- `.github/workflows/ci.yml`: macOS runner → `brew install xcodegen` →
  `xcodegen generate` → `xcodebuild test` on an iPad simulator found via
  `xcrun simctl list`. Check the current macOS runner image / Xcode version
  before pinning one.

## Packages
None. Only Apple frameworks: SwiftUI, PencilKit, CoreText, WebKit (export test
only), UniformTypeIdentifiers.

## Fonts
- **Logo fonts:** bundle 4–6 **SIL Open Font License** fonts (one bubbly, one
  bold geometric, one rounded, one script, one blocky). Lilita One is the
  first one, because the export gate uses it. Prefer static, single-weight files.
- **UI fonts:** static instances of Inter (400/600/700) and Bricolage
  Grotesque (800). Never the variable files, because weights from variable
  fonts registered via `UIAppFonts` are unreliable.
- Add each font's `OFL.txt` to the bundle. **Don't use SF Pro or system
  fonts for logo text.** Apple's font license doesn't allow them in user logos.

## v1.1 (deferred, don't build yet)
- **Time-lapse replay:** strokes already carry timestamps (`PKStrokePath.creationDate`,
  `timeOffset`), so replay = re-adding strokes over time, recorded to MP4 with `AVAssetWriter`.
- **Hold-to-snap shapes:** detect a pause at the end of a stroke, fit a
  line/circle/rectangle, then replace the stroke.
- **Pressure ink in SVG:** outline each stroke by offsetting ± size/2 along
  the normals and export a filled polygon.
- **Brand kit PDF:** logo variants (color/mono/inverted), palette hex codes, font name.
- **Pro unlock (StoreKit 2)**, one-time. If Kids category: parental gate before any purchase.
