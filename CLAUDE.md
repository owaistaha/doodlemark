# CLAUDE.md — Doodlemark (iPad doodle-to-logo app)

## What this app is
Native iPadOS app (Swift/SwiftUI + PencilKit). The user doodles on a faded Sketch
layer, inks clean constant-width lines on top, adds shapes, a name and a
3-color palette, previews it on mockups and exports **SVG + transparent PNG**.
Fully offline, with no backend, account or network. Read `PRD.md` for scope, `DESIGN.md` for the look,
`TECH_SPEC.md` for how, and `PROCREATE_TEARDOWN.md` for why. Open risks are tracked in `RISKS.md`.

## Source of truth
When the docs disagree: **PRD.md > CLAUDE.md > DESIGN.md > TECH_SPEC.md**.
`PROCREATE_TEARDOWN.md` and `PROCREATE_FEATURE_INVENTORY.md` are background
research only. Their "v1" marks don't add scope.

## Stack
Swift 6, SwiftUI, PencilKit, Core Text, WebKit (export test only). iPadOS 17.0+
deployment target, tested on the iPadOS 26.5 simulator (don't download older runtimes).
XcodeGen generates the project from `project.yml`. No third-party packages.

## Before you start

**Human must do (Claude Code can't):**
1. Have Xcode installed and signed in with an Apple ID (Xcode → Settings →
   Accounts) for on-device runs. Copy `Local.xcconfig.example` to
   `Local.xcconfig` (gitignored) and set `DEVELOPMENT_TEAM` to your Team ID
   (a free personal team is fine). Never put the Team ID in `project.yml`.
2. Plug in the iPad, trust the Mac, and turn on Developer Mode on the iPad
   (Settings → Privacy & Security).
3. Approve the font picks. Claude downloads them into
   `Doodlemark/Resources/Fonts/`, each with its `OFL.txt`.
   - UI fonts: **static** instances of Inter (400/600/700) and Bricolage
     Grotesque (800). Never the variable files.
   - Logo fonts: 4–6 OFL fonts, starting with Lilita One (used by the
     export gate). Prefer static, single-weight files.
4. Work through `DEVICE_CHECKLIST.md` on the iPad, then do the on-device
   test in the Definition of done: finger first, then a Pencil/stylus if you
   have one.
5. Create the public GitHub repo and record the demo video.

**Claude Code can do itself:**
- `brew install xcodegen` (if missing), `xcodegen generate`
- Download the approved OFL fonts (with `OFL.txt`) at dev time
- Write all Swift files, tests and the font plist entries (`UIAppFonts`)
- `xcodebuild` build + test on an iPad simulator, found by running
  `xcrun simctl list devices available | grep iPad`. Don't hardcode a device name.

## Bootstrap sequence
1. `xcodegen generate`, then build the empty app on a discovered iPad simulator.
2. Write `Export/SVGExporter.swift` + `Export/GlyphPaths.swift` + model types
   (`Models/`). No UI yet.
3. **Hard gate:** write `DoodlemarkTests/SVGExportTests.swift` as described in
   TECH_SPEC "Hard gate": a code-built drawing + shape + text, exported to SVG,
   rendered with WKWebView vs native render, pixel diff < 2%. It must pass
   before step 4. Also add a debug-only screen with a bare Ink canvas and an
   "Export SVG" button so the human can check the SVG in Safari on a real device.
4. Canvas screen: Sketch `PKCanvasView` (faded, pencil ink) + Shapes overlay +
   Ink `PKCanvasView` (monoline, vector eraser) + Text overlay, layer switcher,
   undo/redo, grid, symmetry.
5. Palette picker, shape tools, text tool (bundled fonts only).
6. Project storage + autosave + gallery + prompt cards on the New screen.
7. Mockup preview (app-icon tile, round sticker) + share sheet export (SVG + PNG).
8. First-canvas 3-tip overlay.
8b. **Learn mode:** `Learn/StrokeScorer.swift` + `StrokeScorerTests` FIRST
   (pure logic, no UI), then the lesson JSON loader + 5 lessons, the Learn tab,
   the lesson player (canvas in lesson mode), the complete screen and
   "Make it yours".
9. CV polish: remaining unit tests, `.github/workflows/ci.yml`, README.md
   (feature list, Mermaid architecture diagram, exporter explanation,
   decisions & trade-offs, run steps, placeholder for the demo GIF).
10. Final build, then hand to the human for the device test.

## Hard rules
- **Every step adds its device-only checks to `DEVICE_CHECKLIST.md`**
  (numbered, with the expected result and a checkbox), not only to the
  step's report.
- **Follow `DESIGN.md`** for every color, font, size and radius. Put them in
  `Theme.swift` as tokens and never hard-code a hex in a view. Text on
  tangerine is always ink. Flat paper/white surfaces, no Liquid Glass styling.
- **Finger drawing must work.** `drawingPolicy = .anyInput` is the default on
  both canvases. Never use the deprecated `allowsFingerDrawing`. Never ship a
  feature that only works with a Pencil (no pressure, tilt, hover or
  double-tap requirements). Test every tool with a finger in the simulator.
- One finger draws, two fingers pan/zoom. Don't add one-finger pan on the
  canvas, because it fights with drawing.
- **Ink layer uses `.monoline` ink only and `PKEraserTool(.vector)` only.** The
  pixel eraser creates `stroke.mask`, and pressure inks change width, and the
  SVG exporter doesn't handle either. Don't "add a nicer pen" to Ink.
- **Always apply `stroke.transform`** when reading stroke points. Skipping it
  works until the user moves a stroke with lasso, and then the export is shifted.
- **Export text as glyph outlines, never `<text>`.** The file must look right on
  machines that don't have the font.
- **Never use SF Pro / system fonts for logo text.** Their license forbids it.
  Only the bundled OFL fonts are offered in the font picker.
- **Shapes have one geometry function** used by both the on-screen renderer
  and the SVG exporter. Two separate implementations will drift apart.
- **The Sketch layer is never in the SVG.** The PNG export also hides it.
- **No network code at all.** No URLSession, analytics SDKs, crash reporters or
  remote fonts. This is a privacy promise for kids, not an oversight.
- Don't save on every stroke. Debounce 1s and write atomically.
- An empty export (no ink, shapes or text) shows a friendly "Draw something
  first." message (no emoji, per DESIGN.md). Never share a blank SVG.
- No splash screen and no multi-page onboarding. The app opens to the gallery.
- Big touch targets (≥ 44pt; ≥ 56pt for main tools). Kids are the primary user.

- **Learn scoring is deterministic maths only**: resample → Fréchet → smoothness
  → stars. No ML, no network, no random feedback. The same stroke always gets
  the same score (tests rely on it).
- Never show a 0-star result as "failed". Say "Almost! Try once more" and
  offer Redo. Kids quit when they're told they failed.
- Lesson coordinates use the same 1024 canvas space as projects. Never
  hand-convert to screen points; go through the canvas transform. Scoring
  thresholds are in that space too. Never scale them by zoom.

## Folder structure
```
Doodlemark/
  App/
    DoodlemarkApp.swift         (AppModel: gallery ↔ New logo ↔ canvas; saves on background)
    Theme.swift                 (tokens from DESIGN.md)
    Components.swift            (Primary/Secondary buttons shared by every screen)
  Models/
    Project.swift               (Project, LogoShape, LogoText, HexColor)
    Palettes.swift              (12 curated 3-color sets; fills are palette slots)
    Prompts.swift               (the 10 starter prompts; PromptDeck shows 9, Shuffle)
    LogoFonts.swift             (the 5 bundled logo fonts; the only ones the picker offers)
  Canvas/
    CanvasScreen.swift
    CanvasTips.swift            (the 3 first-canvas tips: shown once, anchored to their controls)
    CanvasModel.swift           (editor state: tool, layers, pen, zoom, change → undo)
    CanvasHistory.swift         (one snapshot undo history for all four layers, 100 steps)
    HistoryUndoManager.swift    (system undo → our history; PencilKit undo off)
    StrokeSmoother.swift        ("Smooth my lines": Ink only, corners and ends pinned)
    CanvasViewport.swift        (one zoom/offset for every layer)
    LineSize.swift              (Line size ↔ PencilKit tool width; the only conversion)
    PencilCanvas.swift          (UIViewRepresentable around the layer stack)
    InkPalette.swift            (Ink lines ↔ palette slots: recolor by slot)
    SlotColorPicker.swift       (tap and hold a swatch: system color picker popover)
    ShapesLayer.swift
    TextLayer.swift
    Symmetry.swift
    ShapeGeometry.swift         (single source of truth for shape paths)
    ShapeEditing.swift          (move/resize/turn/snap/flip/hit-test maths on path bounds)
  Export/
    SVGExporter.swift
    GlyphPaths.swift
    PNGExporter.swift           (Shapes + Ink + Text render: thumbnails, mockups and the PNG export)
    ExportFiles.swift           (export options, file names, writes SVG/PNG to a temp folder, cleanup)
  Learn/
    Lesson.swift                (Codable lesson + step: name, tip, how, ink points or a shape; 3 stars a step)
    LessonLibrary.swift         (loads + validates the bundled JSON, easy → harder)
    StrokeScorer.swift          (resample, Fréchet, smoothness, stars, fixed feedback copy)
    ScoringConfig.swift         (thresholds)
    LearnProgressStore.swift    (Documents/learn.json: best stars, never lowered; where a lesson was left)
    LessonSession.swift         (one play: steps, raw-stroke scoring, Redo/Next/Skip/Place it, resume, Make it yours)
    LessonGhost.swift           (dashed targets, start dot + arrow in the canvas stack; targets as Ink strokes)
    LearnScreen.swift           (Learn tab: lesson cards with line-art previews, stars pill, logo tip)
    LessonPlayer.swift
    LessonCompleteScreen.swift
  Storage/
    ProjectStore.swift          (schema-versioned files, one atomic folder swap per save, list/rename/duplicate/delete)
    ProjectAutosaver.swift      (1 s debounce + save now)
    ThumbnailCache.swift
  Debug/
    ExportDebugScreen.swift     (DEBUG builds only: bare Ink canvas + SVG preview + share)
    CanvasSpikeScreen.swift     (DEBUG builds only: step 4a mirror-undo + routing spike)
    DebugLinks.swift            (DEBUG builds only: links to the two screens above)
    DebugLaunch.swift           (DEBUG builds only: -resetProjects, -seedSampleProjects, -openNewLogo, -resetLearnProgress …)
  Screens/
    GalleryScreen.swift
    GalleryModel.swift          (gallery state and actions, "Edited …" labels)
    NewLogoSheet.swift          (full screen: blank or a prompt → Start drawing)
    PalettePicker.swift
    ExportScreen.swift          (Preview & export: mockups + export panel + share sheet)
    MockupPreview.swift         (app icon, sticker, tiny test, light & dark from the real render)
  Resources/
    Lessons/                    (rocket, bolt-shield, star-club, cat-badge, moon-cafe .json)
    Fonts/                      (UI: static Bricolage Grotesque 800 + Inter 400/600/700; logo: Lilita One,
                                 Bungee, Sniglet ExtraBold, Pacifico, Poppins ExtraBold; each with <Family>-OFL.txt)
    Assets.xcassets
  Settings.bundle/              (one switch: "Show drawing tips again")
DoodlemarkTests/
  SVGExportTests.swift          (the hard gate; images → GateOutput/, gitignored)
  TextToolTests.swift           (fonts, blocked characters, tracking/caps, typing undo, text in SVG)
  ProjectStoreTests.swift       (round trip, crash anywhere in a save → full old or new, broken projects, duplicate/delete)
  StrokeScorerTests.swift       (stars, direction, length, wobble, determinism)
  LessonLoaderTests.swift       (lessons parse and self-score 3★; fairness check → GateOutput/learn-calibration.txt)
  LearnProgressTests.swift      (learn.json round trip, best never drops, resume, raw vs smoothed, Skip, Make it yours saves + exports)
  CanvasTipsTests.swift         (shown once, skip, show again)
  ExportTests.swift             (SVG = gated exporter, PNG vs native, background, file names, no sketch, cleanup)
  AutosaveTests.swift           (debounce on a manual clock, save now, thumbnails)
  MonolineWidthTests.swift      (documents PencilKit's monoline width law)
  Gate/                         (GateConfig thresholds, renderers, metrics, fixtures)
  Snapshots/                    (byte-exact expected SVGs)
DoodlemarkUITests/              (real synthesized touches: stored widths, spikes, canvas, gallery + relaunch,
                                 the whole rocket lesson traced along its curves via TouchSynthesis.swift)
Config/
  Base.xcconfig                 (committed; optionally includes ../Local.xcconfig)
Local.xcconfig.example         (committed template; copy to Local.xcconfig, gitignored)
project.yml
RISKS.md
DEVICE_CHECKLIST.md           (hand checks on a real iPad, added to by every step)
```

## Definition of done for v1
On a physical iPad, using a finger (and an Apple Pencil or stylus if one is
available), someone who has never seen the app
sketches a logo, inks it, adds a name and a palette, and exports an SVG.
Opened in Safari, the SVG looks the same as the canvas (same shapes, lines,
text and colors, nothing missing or shifted). The project is still in the
gallery after a force-quit and relaunch.
