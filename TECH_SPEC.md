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
Five lessons, in this order (`LessonLibrary.ids`): `rocket`, `bolt-shield`,
`star-club` (Easy), `cat-badge`, `moon-cafe` (Medium). Each step also has a
short `name` ("The fins"), the `tip` (the big line, "Give it fins so it
looks like it's flying") and `how` ("Start on the blue dot…"), as in
design/Lesson.png; lessons have `teaches` for the card ("learn curves and
Mirror"). A shape step has `"shape": {"kind", "center", "size", "rotation",
"fill"}` (fill = palette slot). `LessonLibrary.validate` checks: 3 colors,
4–8 steps, every point inside 0…1024, Mirror lessons only left of x = 512,
ink strokes at least 40 pt long. Example (trimmed):
```json
{
  "id": "rocket",
  "title": "Rocket in 5 strokes",
  "teaches": "learn curves and Mirror",
  "level": 1,
  "palette": ["#FF5A1F", "#1C1B22", "#FFC93C"],
  "mirror": true,
  "steps": [
    {
      "name": "The badge", "tip": "Every logo needs a home",
      "how": "Tap the circle to drop it in. Big and simple works best.",
      "kind": "shape",
      "shape": {"kind": "circle", "center": [512, 476], "size": 680, "rotation": 0, "fill": 0}
    },
    {
      "name": "The fins", "tip": "Give it fins so it looks like it's flying",
      "how": "Start on the blue dot and follow the dashed line: down, out, then back in.",
      "kind": "ink",
      "points": [[445, 512], [414.5, 563], [384, 613], [422.5, 595.5], [461, 578]],
      "width": 18
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
   it's a miss. Both lengths are measured on lines resampled with points at
   least `lengthSampleSpacing` = 8 pt apart (at most 64 points), so wiggles
   finer than that count as wobble, not as extra length, even on a short
   step (a shaky stroke along the whole line isn't "too long").
   Too short → "Try drawing the whole line". Too long says "Stop when you
   reach the end" only if the stroke really traced the line and kept going:
   cut where it comes closest to the target's end (or start, drawn
   backwards), the head must be the right length and a 3-star match.
   Otherwise the tip names the real problem: "very wobbly" if it's within
   60 pt and shaky, else "stay close to the dashed line".
6. Stars: Fréchet ≤ 18pt → 3★ · ≤ 36pt → 2★ · ≤ 60pt → 1★ · else 0★ (redo).
   Thresholds are in 1024 canvas space only. Strokes are read in canvas
   space, which is already zoom-independent, so never scale by `canvasZoom`.
   Drop one star if smoothness is worse than a threshold, and say so in the tip.
   Smoothness is the user's mean turning **minus the target's** (so a corner
   the target has, like the lightning bolt's, isn't wobble), and wobble never
   takes a stroke below 1 star on its own. Going the other way round costs
   nothing; the tip just mentions the blue dot.
7. Tip text is picked from fixed copy by the main problem
   (shape / direction / length / wobble). No generated text.

Starting thresholds come from testing on a real iPad with a finger. Make them
constants in `ScoringConfig.swift`, not magic numbers. Until then,
`LessonLoaderTests.testThresholdsAreFairToWobblyFingers` traces every lesson
step with simulated fingers (the gate's wobble at several strengths plus a
slow drift off the line, through real PencilKit strokes) and writes the star
spread to `GateOutput/learn-calibration.txt`. It asserts that the thresholds
are fair: steady → 3★, ordinary → mostly 2–3★ and never a redo, 30 pt off →
never 3★, 70 pt off → redo, and sloppy / way-off redos are told about
wobble or the line, not length (≤ 20% length tips). `wobbleLimit` = 0.25 rad
came from that run.

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

## First-canvas tips (step 8)
`Canvas/CanvasTips.swift`. `CanvasTipsModel` decides (UserDefaults
`canvasTipsSeen`; set on the last "Got it" or "Skip tips", so leaving
midway shows them again). The Settings.bundle switch `showCanvasTipsAgain`
clears it once and turns itself off. Controls report their frames with
`canvasTipAnchor(_:)` (an anchor preference), and one overlay on the canvas
screen draws the dimmed layer with a hole, the ring and the card, so the
tips follow the real layout in any orientation. The dimmed layer takes all
touches, so nothing is drawn under the tips. DEBUG flags:
`-resetCanvasTips YES`, `-hideCanvasTips YES` (every other UI test).

## Data model (files, no database)
```
Documents/Projects/<uuid>/
  project.json      // "schemaVersion": 1 + the Project fields (flat, sorted keys)
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

struct LogoText: Codable {   // at most one per project (PRD)
  var string: String          // as typed: ≤ 24 characters, all drawable in the font
  var fontName: String        // PostScript name of a bundled logo font (LogoFonts)
  var center: CGPoint         // centre of the line's typographic box
  var pointSize: CGFloat      // 24…400
  var rotation: Double
  var fill: PaletteSlot       // 0/1/2
  var tracking: CGFloat       // letter spacing in 1/1000 em, −50…400
  var allCaps: Bool           // draw `string.uppercased()`; the typed string is kept
}
```
**Shape bounds (step 5):** selection handles, hit-testing and snapping use the
shape's real path bounds (`ShapeGeometry.path(for:).boundingBoxOfPath`), never
the `size × size` box. A regular star is narrower than its box, and its bounds
sit higher than its `center` (its bottom points reach cos 36° of the radius).

## Storage (step 6)
`Storage/ProjectStore.swift` (files), `Storage/ProjectAutosaver.swift`
(when), `Storage/ThumbnailCache.swift` (gallery pictures).
- **Format:** `project.json` is `ProjectFile`: the `Project` fields plus
  `"schemaVersion": 1` at the top level. A file with a newer version isn't
  opened (it shows as broken, never rewritten); migrations from older
  versions go in `ProjectFile.init(from:)`. The folder name is the project id.
- **Atomic saves (one folder swap):** a save writes every file (sketch,
  ink, thumbnail, `project.json`) into a fresh staging folder,
  `Projects/.staging/<id>-<uuid>/` (hidden, same volume), and then swaps
  the whole folder in with `FileManager.replaceItemAt` (`rename(2)` with
  `RENAME_SWAP` on APFS, atomic; a first save is a plain `moveItem`). So
  all four files always come from the same save. That matters because Ink
  colors are linked to palette slots by exact color: an `ink.drawing` from
  one save next to a `project.json` from another could break recolor. A
  crash at any point leaves the full old save or the full new one, never a
  mix; a first save that dies leaves no folder (no empty or error card).
  Rename is a folder swap too (the other files copied over byte for byte).
  Staging folders are never listed or read; the next save of that project
  clears its own, and launch clears them all (`removeLeftovers`, which also
  removes step 6's old `.saving-` temp files). An ordinary failure (disk
  full) removes its staging folder and keeps the old save.
  `ProjectStoreTests` cuts a save off after every step and half-way through
  every file, relaunches, and compares the folder byte for byte with the old
  and new saves.
- **When:** `ProjectAutosaver` watches the model's project and both drawings
  (Observation), so every change counts: strokes, shapes, text, palette,
  Mirror/Grid, the name. It saves **1 s after the last change** (a burst of
  strokes or a typing session is one write), and **right away** when you
  leave the canvas and when the app goes inactive or to the background
  (which also covers a force-quit from the app switcher). Saves run on the
  main actor: a project is a few hundred KB and the save happens while
  nothing is being drawn. `updatedAt` is stamped on the saved copy. A new
  project nobody touched is never written (New logo → Back leaves no empty
  card). Undoing back to the saved state writes nothing. A failed save shows
  "Couldn't save" in the top bar and the next change tries again.
- **Loading:** `ProjectStore.load` reads all three files and puts
  `.monoline` back on every Ink stroke, because a reload reports them as
  `.pen` (RISKS #11). Pixels and export are unchanged either way.
- **Broken projects:** a folder whose `project.json` can't be read (garbage,
  missing, newer version, odd folder name) is listed as a "Couldn't open this
  logo" card with Delete. A project whose drawings fail to load when opened
  turns into that card too. Never a crash, never silently dropped.
- **Thumbnails:** `thumb.png`, 512 px, rendered by `PNGExporter` (the same
  Shapes → Ink → Text drawing the PNG export uses, transparent, no Sketch).
  With no thumbnail (render failed) the save has none rather than an older
  one that no longer matches.
  A project that only has a sketch shows the sketch at 60% instead, so the
  card isn't blank. Rewritten on every save. The gallery decodes them off the
  main thread into an `NSCache` keyed by id + `updatedAt`.
- **Gallery actions:** Rename changes only the name (not "last edited").
  Duplicate is a deep copy into a new folder ("<name> copy", edited now).
  Delete removes the folder (only ever a folder directly inside `Projects/`).
  Names are trimmed and at most 40 characters; an empty name keeps the old one.

## Preview & export (step 7)
`Export/ExportFiles.swift` (files, no UI), `Screens/ExportScreen.swift`
(screen, panel, share sheet), `Screens/MockupPreview.swift` (mockups).
- **Entry:** "Preview & export" in the canvas top bar. If there's no Ink,
  shape or text (`ExportFiles.isEmpty`; a sketch alone counts as nothing),
  it shows "Draw something first." and nothing opens. Otherwise it ends
  typing, saves, and opens the screen full screen over the canvas.
- **Mockups** all use the real `PNGExporter` render: app-icon tile (logo on
  paper, continuous corners at 22.5%), round sticker (white rim, circle
  crop, on `pencilBlue`), tiny test at 96/48/24/16 pt (each rendered at its
  own size × screen scale, never scaled down from a big render, so thin
  lines look as they will), light & dark (transparent logo on paper and on
  ink).
- **Panel:** SVG and PNG 1024 × 1024 cards (both on by default; with
  neither, "Export & share" is off and the line under the name says "Pick
  SVG, PNG or both."), Transparent background (PNG only; off = paper
  `#FBF8F2`, never a rectangle in the SVG), File name (defaults to the
  project name in kebab-case; `ExportFiles.fileName` folds accents, keeps
  ASCII letters, digits and `_`, turns everything else into single dashes,
  no slashes or dots, at most 60 characters, empty → the project name). The
  line under the field shows what the name became ("Saves pizza-rocket.svg
  and pizza-rocket.png").
- **Files:** SVG = `SVGExporter.svg(project:ink:)` (the gated exporter),
  byte for byte. PNG = `PNGExporter` (the thumbnails' renderer) at 1024,
  sRGB. Neither takes a sketch parameter, so the Sketch layer can't reach
  them. Written into `tmp/Export-<uuid>/`, shared with
  `UIActivityViewController` (popover from the button), and the folder is
  removed when the share sheet closes (shared or not). Launch removes any
  `Export-` folder left by a kill while the sheet was open.
- **Save Image:** `NSPhotoLibraryAddUsageDescription` (add-only access) is
  in the Info.plist, so Save Image from the share sheet asks once instead of
  crashing.
- **Tests:** `ExportTests` (SVG equals the gated exporter, PNG vs the gate's
  native render, transparent vs paper, file names, empty and sketch-only
  refusal, sketch in neither file, temp cleanup, mockup renders),
  `ExportUITests` (refusal alert; share sheet opens with the named files,
  and they're gone after it closes).

## Palette
- 12 curated 3-color palettes in `Models/Palettes.swift`. Rules, checked by
  `PaletteTests`: the second color is the darkest (the default Ink pen draws
  dark lines whatever the palette) with ≥ 3:1 contrast against the other two
  (WCAG's minimum for graphics); the three colors are clearly different
  (CIE76 ΔE ≥ 25); each shows on the white canvas (≥ 1.4:1 against white).
- Shapes and text store a **palette slot** (0/1/2), never a hex. The screen
  and the exporter resolve it through `project.palette`, so changing a
  slot's color recolors everything that uses it.
- Ink lines follow their slot too; see "How Ink lines follow a slot" below.
- Tap a swatch = current color (Ink pen, new shapes, and the picked shape's
  fill, one undo step). "Try another" = the next curated palette. Tap and hold = the system
  color picker (`UIColorPickerViewController`, a popover from UIKit, because
  SwiftUI's `ColorPicker` only opens from its own color well). Every color it
  shows applies live; closing it makes the whole change one undo step (none
  if the color ended up the same). Slot strokes are taken from the drawing as
  it was when the picker opened, so passing through another slot's color
  never merges two slots' lines.
- The undo snapshot includes the palette.

### How Ink lines follow a slot (`Canvas/InkPalette.swift`)
**The link is the exact color.** A `PKStroke` can't hold a palette slot: it
has no custom data and no stable ID (mirror copies even share their source's
creation date), so a side table keyed by stroke would break on erase, undo,
smoothing, mirroring and reload. Its color, however, survives all of those
unchanged. The Ink pen only ever draws palette colors, so a line belongs to
the slot whose color is exactly its color (sRGB hex, light appearance). When a
slot's color changes, only those lines' `stroke.ink.color` is rewritten; ink
type, points, widths and transform stay as they are.

**Why the +3 nudge.** The link only works while the three slots have three
different colors. If a slot were given exactly another slot's color, their
lines would merge for good: the next change to either slot would drag both
sets of lines along. So a color picked for a slot that another slot already
has is nudged by 3/255 in one channel: green first (+3, or −3 near 255),
then red, then blue, whichever the other two slots don't have. Three steps
of 255 can't be seen, and the SVG gets the nudged hex (tested: never more
than 3/255 in one channel, `PaletteTests`). At least three of the six
nudges stay in range and two other slots can block at most two of them, so
one always fits.

**Limits.**
- It relies on PencilKit giving back the exact color it was given. That's
  tested for finger strokes (UI test) and for save → reload (byte-identical
  SVG, `DrawingPersistenceTests`). If a future PencilKit rounded colors
  differently, lines would stop following palette changes: they'd keep
  their old color, never get a wrong one. The step 6 reload test re-checks it.
- A line in a color that isn't in the palette (none can be drawn in v1;
  possible from a future import) never follows a slot.
- Two slots can't hold the exact same color: someone who wants two slots
  identical gets them 3/255 apart. "Try another" palettes always have three
  distinct colors (`PaletteTests`).
- A typed hex can export up to 3/255 off when it equals another slot's
  color. Every other color exports exactly as picked.

## Shapes (step 5b)
All the maths is in `Canvas/ShapeEditing.swift` (pure, unit-tested); the
gestures live in `CanvasStackView` and only feed it numbers.
- **Add:** a tile per kind (drawn by `ShapeGeometry` in the current color)
  adds that shape at (512, 512), size 320, in the current slot, and picks it.
- **Pick:** tap. The topmost shape whose outline contains the point wins;
  failing that, the topmost whose path bounds (+ 8 pt slop) contain it, so a
  tap between a star's arms still picks the star. Empty canvas = nothing picked.
- **Move:** one finger on any shape drags it (and picks it). Its centre stays
  on the canvas.
- **Resize:** one finger on a corner handle of the picked shape (handles on
  the path bounds, 26 pt drawn, 64 pt touch target). The box and handles are
  drawn 15 view points outside the bounds, so a handle never covers a star's
  tip or the first/last letter, and are pulled in to stay whole inside the
  canvas view at its edges (it clips). Drawing and hit testing share one
  function (`ShapeSelectionView.handlePoints`). Size follows the
  finger's distance from the centre, so the corner stays under the finger;
  size is kept in 40…1400.
- **Two fingers:** if their midpoint is on the picked shape (bounds + 40 pt),
  they move, resize and turn it; anywhere else they pan and zoom the canvas
  as before. Increments are accumulated and the midpoint re-based when a
  finger lands or lifts, so the shape never jumps.
- **Snapping:** the centre of the path bounds snaps to x = 512 and/or
  y = 512 within 10 view points (so it feels the same at any zoom); tangerine
  guide lines show while snapped. Rotation always moves in 15° steps.
- **Flip / Delete** for the picked shape, in the panel. All four kinds are
  mirror-symmetric about their own vertical axis, so a flip is a rotation
  (sideways r → −r, upside down r → π − r): no new model field, and
  `ShapeGeometry` stays the only geometry. A flip that wouldn't change the
  outline (a circle, an upright star sideways) is disabled.
- **Undo:** each move/resize/turn gesture is one step. A one-finger drag that
  turns into a two-finger gesture is still one step (nested edit session).
- Drags are measured from the touch-down point, not from the pan
  recognizer's `translation`, which leaves out the ~10 pt it takes the pan to
  start (the shape lagged the finger by that much).

## Text (step 5c)
One logo text per project (PRD). Same code as shapes: `LogoShape` and
`LogoText` both conform to `CanvasItem` (centre, rotation, a `scale` = size or
point size, an outline), and `ShapeEditing`'s move / resize / turn / snap are
generic over it. The gestures carry a `PickedItem` (shape or text), so text
moves with one finger, resizes from a corner handle, and turns and pinches
with two fingers exactly like a shape, one undo step per gesture. No flip for
text (a mirrored word isn't a logo).
- **Typing:** a system `TextField` in the right panel (keyboard, dictation and
  Scribble come with it). The first letter creates the text at (512, 512),
  120 pt, in the current slot, in the chosen font. The whole typing session
  is **one undo step**: the snapshot is taken at the first change and
  recorded when the field loses focus, or when anything else starts (a
  gesture, a control, undo/redo, another tool). Erasing every letter removes
  the text. While a session is open, Undo is enabled and takes it back whole.
- **Blocked characters:** every character is checked against the chosen font
  with `CTFontGetGlyphsForCharacters` (per grapheme, all glyphs ≠ 0; newlines
  refused). Characters it can't draw (emoji, CJK, ★, a missing accent) are
  left out and the field shows a note under it: "This font can't draw “😀”."
  No alert. The field then shows exactly what's on the canvas. Over 24
  characters: "Up to 24 letters and spaces." Switching to a font that can't
  draw the current text, or ALL CAPS without a capital for a letter, is
  refused with a note ("Lilita One can't draw “ő”. Change the text first.").
- **Never a fallback font (RISKS #7):** `GlyphPaths` also checks that every
  Core Text run uses the requested font and throws `.missingGlyphs`
  otherwise, so the exporter fails rather than writing system-font outlines.
- **Tracking** is in 1/1000 em (logo-tool convention), applied as
  `kCTKernAttributeName` = tracking/1000 × point size on every character but
  the last, so the line stays centred on `center`. **ALL CAPS** draws
  `string.uppercased()` and keeps what was typed.
- **Bounds:** hit testing, handles and snapping use the real glyph outline
  bounds (`GlyphPaths.path(for:).boundingBoxOfPath`), as wide as the letters.
  With the Text tool, a drag that starts on those bounds (+ 8 pt) moves it.
- **Keyboard:** the on-screen keyboard covers the bottom ~45% of the screen.
  The canvas area goes compact below 560 pt height (12 pt margins, zoom and
  hint pills hidden) so the whole logo stays visible above the keys. The tool
  rail stays full height behind them (an overlay, so it never makes the row
  taller). When the field is focused, or a note appears, the panel scrolls
  the "Logo name" block to its top so the note is never behind the keys.
- **Export:** text is glyph outlines, one `<path>` in `<g id="text">`; never
  `<text>`, a font name or the string itself. The gate renders "Pizza Rocket"
  in every bundled font at −0.3 rad with tracking (odd fonts in ALL CAPS).

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
  straight target = wobble tip, same stroke = same score), `LessonLoaderTests` (every bundled lesson
  parses and its points are inside 0…1024), `SVGExportTests` (pixel-diff gate), `ShapeGeometryTests`,
  `SymmetryTests`, `ProjectStoreTests` (save → load round-trip, crash anywhere in a save →
  full old or full new save), `ExportTests` (export files vs the gate).
- `.github/workflows/ci.yml`: macOS runner → `brew install xcodegen` →
  `xcodegen generate` → `xcodebuild test` on an iPad simulator found via
  `xcrun simctl list`. Check the current macOS runner image / Xcode version
  before pinning one.

## Packages
None. Only Apple frameworks: SwiftUI, PencilKit, CoreText, WebKit (export test
only), UniformTypeIdentifiers.

## Fonts
- **Logo fonts (step 5c):** five static, single-weight **SIL Open Font
  License 1.1** files from google/fonts, listed in `Models/LogoFonts.swift`
  (the only fonts the picker offers) and `UIAppFonts`:

  | Style | Font (file → PostScript name) | Why |
  |---|---|---|
  | Bubbly | Lilita One (`LilitaOne-Regular.ttf` → `LilitaOne`) | Chunky and friendly; the export gate's font |
  | Blocky | Bungee (`Bungee-Regular.ttf` → `Bungee-Regular`) | Square signage letters, caps-only look |
  | Rounded | Sniglet ExtraBold (`Sniglet-ExtraBold.ttf`) | Soft round ends, very kid-friendly |
  | Script | Pacifico (`Pacifico-Regular.ttf` → `Pacifico-Regular`) | The classic connected logo script |
  | Clean | Poppins ExtraBold (`Poppins-ExtraBold.ttf`) | Bold geometric sans for a clean, modern mark |

  Each has `<Family>-OFL.txt` next to it. Checked when bundled: no `fvar`
  table (static), license is OFL 1.1, Latin + common accents, no CJK. Only
  Lilita One declares a Reserved Font Name ("Lilita"); it's bundled
  unmodified, so that's fine. `TextToolTests` checks each loads by name,
  isn't variable, is in `UIAppFonts` with its license, and draws
  "Pizza Rocket". The picker writes each font's name in that font.
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
