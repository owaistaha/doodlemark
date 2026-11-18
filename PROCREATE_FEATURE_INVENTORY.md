# Procreate: full feature inventory (reverse-engineered)

> **Background research only.** "✅ v1" marks here don't add scope. Scope
> comes from PRD.md (source-of-truth order: PRD > CLAUDE > DESIGN > TECH_SPEC).

**What this is:** every user-facing Procreate feature, collected section by
section from the official Procreate Handbook plus the release notes for every
update since 5.0 (5X, 5.2, 5.3, 5.4). Each feature has a Doodlemark verdict and,
where it matters, the iOS building block you'd use to build it.

**Sources:** Procreate Handbook v5.0 (help.procreate.com/procreate/handbook/5.0),
the Procreate Help Center "What's new in 5.4" article, Procreate's App Store
listing (5.4.14, Sep 2026), and coverage of 5X / 5.2 / 5.3. The 5.4 handbook
pages couldn't be fetched directly, so features added after 5.0 come from release
notes and may be less detailed than the handbook sections.

**Legend**
| Tag | Meaning |
|---|---|
| ✅ v1 | In Doodlemark v1 (often simplified) |
| 🟡 v1.1 | Next version |
| 🔵 Later | Good idea, not soon |
| ❌ Skip | Doesn't fit a logo app or a kids/beginner audience |

---

## 1. Interface

| Feature | What it does in Procreate | Doodlemark | How we'd build it |
|---|---|---|---|
| 3-zone layout | Painting tools top right (Paint, Smudge, Erase, Layers, Color); advanced tools top left (Gallery, Actions, Adjustments, Selections, Transform); sidebar left | ✅ v1, simplified | SwiftUI overlay: tools on the left, layer switcher + color on the right |
| Sidebar sliders | Brush size + opacity; tap for coarse, drag away for fine control | ✅ v1 (size only) | Custom vertical slider |
| Modify button | Tap = eyedropper; can be reassigned | 🟡 v1.1 (eyedropper) | Sample color from rendered canvas |
| Undo/redo buttons | Up to 250 steps, a notice shows what was undone, hold to repeat | ✅ v1 | `UndoManager` shared by PencilKit + our model |
| Dark/Light interface | Toggle in Prefs | ✅ v1 (follows system) | SwiftUI color scheme |
| Left/right-handed UI | Sidebar on either side | 🟡 v1.1 | Mirror the layout |
| Movable sidebar | Drag the sidebar up/down | ❌ Skip | — |
| Brush cursor | Shows the brush shape before you touch | 🔵 Later (Pencil hover only) | `UIHoverGestureRecognizer` |
| Full Screen | 4-finger tap hides the UI | 🟡 v1.1 | Toggle overlay visibility |
| Project Canvas | Shows only the canvas on an external display / AirPlay | ❌ Skip | — |
| Liquid Glass redesign (5.4.5) | Refreshed look for iPadOS 26 | ✅ v1 (comes free with native SwiftUI) | System materials |
| Keyboard shortcuts | Hold ⌘ to see the shortcut map; eyedropper, undo, colors, adjustments, selections… | 🟡 v1.1 (undo/redo, tools) | `.keyboardShortcut` |
| Scribble | Handwrite text into fields (layer names, values, text) | ✅ v1 (free with system text fields) | Works automatically in `TextField` |
| Accessibility: Dynamic Type, VoiceOver, feedback sounds | System accessibility support | ✅ v1 (VoiceOver labels + Dynamic Type for UI) | SwiftUI accessibility modifiers |
| Accessibility: color naming | Announces the name of colors | 🟡 v1.1 (great for kids and colorblind users) | Nearest-name lookup table |
| Accessibility: assignable single-touch gestures | Alternative to multi-finger gestures | 🟡 v1.1 | Buttons for undo/redo already cover this |

## 2. Gestures

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| 1-finger paint/smudge/erase | Draws with the current tool | ✅ v1 (finger draws, see TECH_SPEC) | `drawingPolicy = .anyInput` |
| Pinch zoom, pinch-twist rotate | Canvas navigation | ✅ v1 zoom; 🟡 rotate | PKCanvasView is a scroll view; rotation needs a custom transform |
| Quick pinch to fit screen | Snap canvas to fit, reverse to go back | ✅ v1 | Zoom-to-fit on a fast pinch |
| 2-finger tap undo / hold for rapid undo | — | ✅ v1 tap; 🟡 hold | Tap gesture recognizer |
| 3-finger tap redo / hold for rapid redo | — | ✅ v1 tap; 🟡 hold | — |
| 3-finger scrub = clear layer | — | ❌ Skip (too easy for kids to trigger by accident) | — |
| 3-finger swipe down = Copy Paste menu | — | ❌ Skip | — |
| 4-finger tap = Full Screen | — | 🟡 v1.1 | — |
| Draw and hold = QuickShape | Snap to a line or shape | 🟡 v1.1 (the top logo feature) | See §8 |
| Layer gestures: pinch to merge, swipe to multi-select, 2-finger swipe = Alpha Lock, 2-finger hold = select contents, 2-finger tap + drag = opacity | Layer panel power gestures | ❌ Skip (fixed layers) | — |
| Gesture Controls prefs | Toggle/reassign every shortcut, hold delay, conflict warning, 1-finger tap QuickMenu | ❌ Skip | — |
| Rapid Undo Delay slider | 0–1.5s | ❌ Skip | — |
| Rotate with pinch zoom toggle | — | 🟡 v1.1 | — |
| Disable touch actions / disable undo-redo gestures | — | ✅ v1 = our "Pencil only" toggle | `.pencilOnly` drawing policy |
| Palm Support level (Off / Standard / Fine) | Advanced setting | ✅ v1 (PencilKit handles palm rejection with Pencil) | Built into PencilKit |

## 3. Apple Pencil

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| Pressure + tilt on brushes | Size/opacity/scatter/color tied to pressure or tilt | ❌ v1 on purpose (works the same for fingers; SVG stays exact) | — |
| Pressure Curve editor | Global curve in Prefs (+ per-brush in 5.4) | ❌ Skip | — |
| Double-tap shortcut | iOS options (eraser / last tool / palette) plus Procreate-assigned actions (Drawing Assist, eyedropper, QuickShape, QuickMenu, Full Screen, clear layer, copy-paste) | ✅ v1 (switch to eraser) | `UIPencilInteraction` |
| Hover (5.3, M2+ iPad Pro) | Brush preview, resize/opacity by hover, hover ColorDrop, UI hover cues, gallery hover previews, freehand selection preview | 🔵 Later | `UIHoverGestureRecognizer` |
| Apple Pencil Pro support (5.3.10) | Support for the Pencil Pro's extra controls | 🔵 Later | `UIPencilInteraction` squeeze |
| Third-party stylus | Bluetooth stylus pairing; since 5.3, non-Apple styluses removed except Logitech Crayon | ✅ v1 better: **any stylus works** (capacitive ones act as a finger) | `.anyInput` |

## 4. Gallery

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| Canvas presets | Screen Size, Square, 4K, A4, 4×6 Photo, US Paper | ✅ v1: square only (logos) | Fixed 1024×1024 |
| Custom canvas | Name, W/H/DPI, mm/cm/in/px, up to 16K, layer count drops with size | ❌ Skip | — |
| Color profile per canvas | RGB (sRGB, Display P3) or CMYK, 19 built-in, import ICC; can't change later | ❌ Skip (sRGB only, the web/SVG standard) | — |
| Time-lapse settings per canvas | 1080p–4K, Low→Lossless, HEVC | 🟡 v1.1 (with time-lapse) | — |
| Canvas background color / hidden background | — | ✅ v1 (transparent by default; preview background toggle) | — |
| Thumbnail grid, rename | — | ✅ v1 | `LazyVGrid` |
| Swipe thumbnail → share / duplicate / delete | — | ✅ v1 (context menu) | `.contextMenu` |
| Select mode, bulk share/duplicate/delete | — | 🟡 v1.1 | — |
| Drag to reorder | — | 🟡 v1.1 | — |
| Stacks (folders) | Drag one artwork onto another | 🔵 Later ("Brands" folders) | — |
| Rotate thumbnail | Two-finger twist | ❌ Skip | — |
| Full-screen preview, swipe between artworks, batch preview | — | 🟡 v1.1 | — |
| Import from Files / Photos, drag-and-drop in | — | ✅ v1 (photo as sketch reference) | `PhotosPicker` |
| Share via iOS share sheet, drag out to other apps | — | ✅ v1 share sheet; 🟡 drag out | `ShareLink` |
| Home Screen canvas widgets (5X) | — | 🔵 Later ("today's logo prompt" widget) | WidgetKit |
| iCloud artwork sync | Promised for Procreate (already in Dreams) | 🔵 Later | — |

## 5. Colors

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| Color button, primary + secondary swatch | — | ✅ v1 (primary only) | — |
| Previous color (hold color button) | — | ❌ Skip | — |
| Color History | Last 10 colors; on all iPads since 5.4 | 🟡 v1.1 | Ring buffer |
| Color Disc | Hue ring + saturation disc, pinch to enlarge, double-tap snaps to white/black/grey/half/full | ✅ v1 (system `ColorPicker` covers this) | SwiftUI `ColorPicker` |
| Classic | Square picker + HSB sliders | ✅ via system picker | — |
| Harmony | Complementary, Split Complementary, Analogous, Triadic, Tetradic | ✅ v1 **as a kid-friendly palette generator** ("make me a matching set") | HSB rotation math |
| Value | HSB + RGB sliders, numeric fields, hex box | ✅ v1 (hex field for young pros) | — |
| Palettes: create, rename, set default, reorder, delete | — | ✅ v1 curated palettes; 🟡 custom saved palettes | — |
| Palettes: compact vs card view | — | ❌ Skip | — |
| Palette import/export (.swatches, Adobe ACO/ASE) | — | 🔵 Later | — |
| Palette Capture (5X) | Build a palette from the camera, a photo or a file | 🟡 v1.1 (fun: "steal colors from your room") | Core Image k-means / dominant colors |
| Example palettes (5.4) | Restorable starter palettes | ✅ v1 (12 curated) | — |
| ColorDrop | Drag the color onto the canvas to flood-fill; hold to adjust threshold | 🔵 Later (vector shapes already have a fill) | — |
| SwatchDrop (5X) | Drag a palette swatch to fill | 🔵 Later | — |
| Continue filling / hover ColorDrop (5.3) | Fill several areas in a row | ❌ Skip | — |
| Color Companion | Detachable mini color panel | ❌ Skip | — |
| Eyedropper | Touch-hold, or Modify button | 🟡 v1.1 | — |
| Color profiles (ICC, CMYK) | — | ❌ Skip | — |

## 6. Brushes

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| Paint / Smudge / Erase share one library | — | ✅ v1 Paint + Erase only | — |
| Smudge tool | Blends pigment, strength via opacity | ❌ Skip (no smudging in vector logos) | — |
| Brush transfer | Hold another tool icon to copy brush settings to it | ❌ Skip | — |
| Brush Library (5.4: Procreate Library + Classic Library) | Multiple libraries; 18 new sets × 10 brushes: Pencils, Pens, Inks, Markers, Pastels, Oils, Paints, Gouache, Watercolors, Charcoals, Basics, Lettering, Comics, Design, Grunge, Street Art, Digital, Creative | ✅ v1: **3 tools**: Sketch Pencil, Ink Pen (monoline), Eraser | PencilKit `PKInk` types |
| Classic default sets (pre-5.4, 18) | Sketching, Drawing, Inking, Painting, Artistic, Calligraphy, Airbrushing, Textures, Abstract, Charcoals, Elements, Spraypaints, Touchups, Vintage, Luminance, Industrial, Organic, Water | ❌ Skip | — |
| Brush Search (5.4) | Swipe down; search by text or emoji | ❌ Skip (3 tools) | — |
| Recent brushes, pin brushes, save size/opacity per brush (5.2) | — | ✅ v1: remember size per tool | `@AppStorage` |
| Organize: add sets, duplicate, rename, delete, move, multi-select | — | ❌ Skip | — |
| Custom set icons / emoji (5.4) | — | ❌ Skip | — |
| Import/export .brush, .brushset, .brushlibrary; Photoshop .abr import | — | ❌ Skip | — |
| iCloud brush sync, Files storage (5.4) | — | ❌ Skip | — |
| **Brush Studio**: 11 attribute groups, 100+ settings | Below | ❌ Skip entirely: the single biggest thing we deliberately don't copy | — |
| ↳ Stroke Path | Spacing, StreamLine, Jitter, Fall Off; 5.4: Spacing Jitter, Jitter Lateral, Jitter Linear | — | — |
| ↳ Stabilization (5.2) | StreamLine, Stabilization, Motion Filtering (+ app-wide setting) | ✅ v1 as **one "Smooth lines" toggle** for the ink pen (great for fingers) | Smoothing in the stroke→SVG fit, plus optional live smoothing |
| ↳ Taper | Pressure taper, touch taper, link tip sizes, tip animation, classic taper | ❌ Skip | — |
| ↳ Shape | Shape editor/source, scatter, rotation, count, count jitter, randomized, azimuth, flip X/Y, roundness graph, pressure/tilt roundness, filtering; 5.4: roundness H/V jitter | ❌ Skip | — |
| ↳ Grain | Grain editor/source/import, moving vs texturized, scale, zoom, rotation, depth, depth jitter, offset jitter, blend mode, brightness/contrast, filtering | ❌ Skip | — |
| ↳ Rendering | Light/Uniformed/Intense/Heavy Glaze, Uniform/Intense Blending, flow, wet edges, burnt edges, blend mode, luminance blending; 5.4: Alpha Threshold | ❌ Skip | — |
| ↳ Wet Mix | Dilution, charge, attack, pull, grade, wetness jitter | ❌ Skip | — |
| ↳ Color Dynamics | Stamp/stroke color jitter (hue, sat, lightness, darkness, secondary), color pressure, color tilt | 🔵 Later ("rainbow pen" for kids, but raster only) | — |
| ↳ Dynamics | Speed → size/opacity, jitter; 5.4: speed → spacing | ❌ Skip | — |
| ↳ Apple Pencil | Pressure → size/opacity/flow/bleed/smoothing/response; tilt graph; 5.4: per-brush pressure graph | ❌ Skip | — |
| ↳ Materials (5.2) | Metallic + roughness for 3D | ❌ Skip | — |
| ↳ Properties | Stamp preview, orient to screen, preview size, max/min size and opacity | ❌ Skip | — |
| ↳ About this Brush | Name, author, picture, signature, reset point | ❌ Skip | — |
| ↳ Drawing Pad + Preview tab (5.4) | Test strokes live; edit thumbnails | ❌ Skip | — |
| Dual Brush | Combine two brushes, combine mode, uncombine | ❌ Skip | — |
| Blur brushes (5X) | Paint blur with a brush | ❌ Skip | — |

## 7. Layers

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| Layers panel, + new layer, custom names | — | ✅ v1 as a **fixed 4-layer switcher** (Sketch / Shapes / Ink / Text) | Segmented control |
| Background Color layer, hide for transparency | — | ✅ v1 (export is transparent; preview background toggle) | — |
| Visibility checkbox | — | ✅ v1 (hide Sketch) | — |
| Primary + secondary (multi) layer selection | — | ❌ Skip | — |
| Groups (create, collapse, Combine Down) | — | ❌ Skip | — |
| Reorder by drag | — | ❌ Skip (fixed order) | — |
| Drag layers to other canvases / Gallery | — | ❌ Skip | — |
| Lock, duplicate, delete | — | ✅ v1 lock Sketch; 🟡 others | — |
| Layer limit by canvas size | — | n/a | — |
| Layer Options: rename, select, copy, fill, clear, invert | — | ✅ v1 "Clear layer" (with confirmation) | — |
| Alpha Lock | Paint only on existing pixels | ❌ Skip | — |
| Layer Mask / Clipping Mask | Non-destructive masking | ❌ Skip (masks complicate SVG) | — |
| Drawing Assist per layer | Snap strokes to a guide | ✅ v1 via symmetry on Ink | See §8 |
| Reference layer | ColorDrop respects linework from another layer | ❌ Skip | — |
| Merge Down / pinch to merge / Flatten | — | ❌ Skip | — |
| Blend modes (25+) | Normal; Multiply, Darken, Color Burn, Linear Burn, Darker Color; Lighten, Screen, Color Dodge, Add, Lighter Color; Overlay, Soft Light, Hard Light, Vivid Light, Linear Light, Pin Light, Hard Mix; Difference, Exclusion, Subtract, Divide; Hue, Saturation, Color, Luminosity | ❌ Skip | — |
| Layer opacity | — | ✅ v1 for Sketch only (the "faded" look) | `.opacity` |
| Share layers (PDF per page, PNG per layer, animated GIF/PNG/MP4 frames) | — | 🟡 v1.1 = "Brand kit" export | — |
| Private layer (5X) | Insert an image that isn't in the time-lapse | 🟡 v1.1 (reference photo stays out of the replay) | — |

## 8. Drawing guides & assistance

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| 2D Grid | Position/rotation nodes, grid size, color, opacity, thickness, assisted drawing | ✅ v1 (fixed grid, toggle) | Canvas overlay |
| Isometric guide | — | ❌ Skip | — |
| Perspective guide | 1/2/3 vanishing points, horizon | ❌ Skip | — |
| Symmetry guide | Vertical, Horizontal, Quadrant, Radial; Mirror vs Rotational; nodes, reset, color/opacity/thickness | ✅ v1 **vertical**; 🟡 horizontal / quadrant / **radial** (radial is amazing for badge logos) | Mirror new strokes (TECH_SPEC) |
| Drawing Assist | "Invisible ruler" snapping strokes to the guide | ✅ v1 (for symmetry) | — |
| QuickShape | Hold to snap: line, arc, poly-line, ellipse→circle, triangle→equilateral, quad→square; second finger = perfect; drag to scale/rotate; 15° rotation snap; Edit Shape nodes | 🟡 v1.1 (**highest-priority v1.1 feature**) | Detect a pause, fit a shape (least squares), replace the stroke with a clean `PKStroke` |

## 9. Text

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| Add Text (vector text box) | Actions → Add → Add Text | ✅ v1 (one name text) | Our model + Core Text |
| Edit Style: font list with previews | ~100 iOS fonts + Procreate fonts (+25 fonts in 5.3 incl. Arabic, Hindi, Thai, Japanese) | ✅ v1: 4–6 **OFL** fonts only (licensing, see CLAUDE.md) | Bundled fonts |
| Style variants (regular, italic, bold…) | — | 🟡 v1.1 | — |
| Design sliders: size, kerning, tracking, leading, baseline, opacity | — | ✅ v1 size + **tracking** (key for logos); 🟡 others | CTFont attributes |
| Attributes: alignment, underline, outline, all-caps | — | ✅ v1 all-caps; 🟡 outline text | — |
| Import fonts (TTF/OTF/TTC, drag-drop, Files, AirDrop) | — | 🔵 Later (licensing warning needed) | — |
| Rasterize text | — | ❌ Skip (we keep it vector) | — |
| Text on a curve / circle | **Procreate doesn't have it** | 🟡 v1.1 (classic badge/emblem logos, a real point of difference) | Lay glyphs along an arc |

## 10. Animation (Animation Assist)

| Feature | Procreate | Doodlemark |
|---|---|---|
| Timeline, play/pause, add frame, flick scroll | — | ❌ Skip |
| Frame options: hold duration (≤120), duplicate, delete, foreground, background | — | ❌ Skip |
| Settings: 1–60 fps, onion skin frames (≤12) + opacity, blend primary, color secondary frames | — | ❌ Skip |
| Playback: One Shot, Loop, Ping Pong | — | ❌ Skip |
| Export: animated GIF / PNG / MP4 / HEVC | — | 🔵 Later: "animated logo reveal" (a different, simpler feature) |

## 11. Page Assist (5.2)

| Feature | Procreate | Doodlemark |
|---|---|---|
| Multi-page sketchbook / comics / storyboards, PDF import, next/previous page in QuickMenu | — | ❌ Skip |

## 12. Selections

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| Automatic (tap + threshold drag) | — | ❌ Skip | — |
| Freehand / polygon (with hover preview in 5.3) | — | 🟡 v1.1 lasso on Ink | `PKLassoTool` (free in PencilKit) |
| Rectangle / Ellipse | — | ❌ Skip | — |
| Add / Remove / Invert / Feather | — | ❌ Skip | — |
| Copy & Paste selection to new layer | — | ❌ Skip | — |
| Save & Load selections; hold to reload last | — | ❌ Skip | — |
| Selection Color Fill (5X) | — | ❌ Skip | — |
| Clear | — | ❌ Skip | — |
| Selection mask visibility slider | — | ❌ Skip | — |
| Select object by tap | (not a Procreate concept) | ✅ v1 for shapes/text | Hit testing |

## 13. Transform

| Feature | Procreate | Doodlemark | How |
|---|---|---|---|
| Freeform / Uniform | — | ✅ v1 uniform scale + rotate for shapes/text | Gestures + handles |
| Distort | Corner perspective, center shear | ❌ Skip | — |
| Warp + Advanced Mesh, fold, node front/middle/back | — | ❌ Skip | — |
| Magnetics / Snapping (5X: snapping distance + velocity) | Blue guide lines | ✅ v1 snap to canvas center + 15° rotation | Simple threshold math |
| Flip H / V | — | ✅ v1 for shapes; 🟡 whole logo | — |
| Rotate 45° | — | ✅ v1 (via 15° snap) | — |
| Fit to Screen | — | ✅ v1 "Center logo" button | — |
| Interpolation (Nearest / Bilinear / Bicubic) | — | n/a (vector) | — |
| Nudge (tap outside the box) | — | 🟡 v1.1 arrow nudges | — |
| Bounding Box Adjust (5X) | Rotate the box itself | ❌ Skip | — |
| Reset | — | ✅ v1 | — |
| Simplified Undos setting | Transform steps = one undo | ✅ v1 (one undo per gesture) | — |

## 14. Adjustments & filters

All of these are pixel effects, so none of them fit a vector logo. Procreate
applies them in **Layer mode** (whole layer) or **Pencil mode** (brushed on with
Pencil Filters, 5X).

| Feature | Options | Doodlemark |
|---|---|---|
| Opacity | — | ❌ |
| Gaussian Blur | Amount | ❌ |
| Motion Blur | Direction by drag | ❌ |
| Perspective Blur | Positional / Directional, disc | ❌ |
| Sharpen | Amount | ❌ |
| Noise | Amount (improved in 5X) | ❌ |
| Bloom (5X) | — | ❌ |
| Glitch (5X) | Four glitch types with controls | ❌ |
| Halftone (5X) | Full Color, Screen Print, Newspaper | 🔵 Later (fun "poster" mockup effect) |
| Chromatic Aberration (5X) | — | ❌ |
| Liquify | Push, Twirl L/R, Pinch, Expand, Crystals, Edge, Reconstruct; size, pressure, distortion, momentum; Adjust / Amount / Reset | ❌ |
| Clone | Source disc, lock disc, any brush, size, strength | ❌ |
| HSB | Hue, saturation, brightness | 🟡 v1.1 as "shift palette hue" (recolors all logo colors at once) |
| Color Balance | RGB↔CMY, shadows/midtones/highlights | ❌ |
| Curves | Gamma + R/G/B, ≤11 nodes, histogram | ❌ |
| Gradient Map (5X) | Gradient library, custom gradients | ❌ |
| Recolor | Crosshair, replacement color, flood | ✅ v1 in vector form: **tap a palette slot to recolor everything using it** |
| Undo / Redo / Reset / Cancel inside each adjustment | — | n/a |

## 15. Actions menu

| Feature | Procreate | Doodlemark |
|---|---|---|
| **Add**: insert file, insert photo, take photo | Image onto canvas (PSDs flattened) | ✅ v1 photo onto the Sketch layer as a reference |
| **Add**: insert private file / photo (5X) | Not recorded in the time-lapse | 🟡 v1.1 |
| **Add**: add text | — | ✅ v1 |
| **Add**: cut / copy / copy all / paste / cut & paste / copy & paste | — | 🟡 v1.1 copy SVG to clipboard (handy for Figma) |
| **Canvas**: Crop & Resize | Rotate, freeform/uniform crop, numeric, resample | ❌ Skip (fixed square) |
| **Canvas**: Animation Assist / Page Assist toggles | — | ❌ |
| **Canvas**: Drawing Guide + Edit Drawing Guide | 2D / isometric / perspective / symmetry | ✅ v1 grid + symmetry toggles |
| **Canvas**: Reference Companion (5X) | Floating window: Canvas (whole artwork preview), Image, Face | ✅ v1 **mockup preview** plays this role; 🟡 small "how it looks tiny" preview (logos must work at 32px) |
| **Canvas**: Flip canvas H / V | — | 🟡 v1.1 (classic trick to spot mistakes) |
| **Canvas**: Canvas Information | Title, author, signature, dates, dimensions, DPI, layer stats, color profile, video settings, stroke count, tracked time, file size | 🔵 Later: "Logo stats" for kids (strokes, time spent) |
| **Share**: .procreate, PSD, PDF (Good/Better/Best), JPEG, PNG, TIFF | — | ✅ v1 **SVG + PNG**; 🟡 PDF |
| **Share**: Share Layers (PDF pages, PNG folder, animated GIF/PNG/MP4) | — | 🟡 v1.1 brand kit |
| **Video**: Time-lapse Replay | Loops at 30fps, scrub, pinch-zoom | 🟡 v1.1 |
| **Video**: Time-lapse recording toggle, purge / don't purge | — | 🟡 v1.1 |
| **Video**: Export full length or 30 seconds | 30s keeps more early frames | 🟡 v1.1 (the TikTok/LinkedIn growth loop) |
| **Video**: HEVC with alpha (5X) | — | 🔵 Later |
| **Prefs**: interface toggles, rapid undo, selection mask, stylus, pressure curve, gesture controls | — | ✅ v1 minimal settings: Pencil-only, smooth lines, left/right hand later |
| **Help**: restore purchases, advanced settings, Learn to Procreate, support, portfolio, review | — | ✅ v1 "How to" tips + 🟡 support link |
| **Advanced (iPad Settings)**: canvas orientation memory, fit canvas inside interface, palm support, disable time-lapse, simplified undos, max speed distance, drag-and-drop export format | — | ❌ Skip |

## 16. QuickMenu & copy-paste menu

| Feature | Procreate | Doodlemark |
|---|---|---|
| QuickMenu: radial menu with 6 customizable buttons; tap or flick; defaults New Layer, Flip H, Copy, Merge Down, Clear Layer, Flip V | — | ❌ Skip (too hidden for kids) |
| Copy Paste menu (3-finger swipe down): Cut, Copy, Copy All, Paste, Cut & Paste, Copy & Paste | — | ❌ Skip |

## 17. 3D painting (5.2 / 5.3)

| Feature | Procreate | Doodlemark |
|---|---|---|
| Import OBJ / USDZ with UV maps; paint with every brush; texture-flattened view | — | ❌ Skip |
| PBR materials: metallic + roughness; respects normal / AO maps | — | ❌ Skip |
| Lighting Studio: up to 4 lights, 11 environments | — | ❌ Skip |
| AR View (LiDAR), animated 3D turntable export, OBJ/USDZ export | — | 🔵 Later: "see your logo on your wall in AR" (simple RealityKit plane, a different feature) |

## 18. AR FacePaint (5X)

| Feature | Procreate | Doodlemark |
|---|---|---|
| Paint on your own face live via the front camera (TrueDepth), animations play on the face | — | 🔵 Later: "wear your logo" filter for kids (fun, but needs ARKit face tracking) |

## 19. File formats

| Format | Procreate import | Procreate export | Doodlemark v1 |
|---|---|---|---|
| .procreate (layers + time-lapse inside) | ✅ | ✅ | Own project folder (not shareable in v1) |
| PSD (layers, blend modes) | ✅ | ✅ | ❌ |
| PDF (multi-page) | ✅ (5.2) | ✅ | 🟡 v1.1 |
| JPEG / PNG / TIFF | ✅ | ✅ | PNG export ✅ (transparent, 1024px) |
| GIF / animated PNG / MP4 / HEVC | ✅ (GIF) | ✅ | 🟡 time-lapse MP4 |
| OBJ / USDZ | ✅ | ✅ | ❌ |
| .brush / .brushset / .brushlibrary / .abr | ✅ | ✅ | ❌ |
| .swatches / ACO / ASE | ✅ | ✅ (.swatches) | 🔵 Later |
| TTF / OTF / TTC fonts | ✅ | — | 🔵 Later |
| **SVG** | ❌ | ❌ | ✅ **v1: the whole point of the app** |

## 20. Business model & platform

| Item | Procreate | Doodlemark |
|---|---|---|
| Price | $12.99 one-time; Pocket $5.99; Dreams $19.99; no bundle | Free in v1; later a one-time Pro unlock |
| Trial / free tier | None | Free core app, first logo always free |
| Platforms | iPad (Procreate), iPhone (Pocket), Dreams on iPad | iPad only (v1) |
| Data collection | "Data Not Collected" privacy label | Same, fully offline |
| Updates | Free lifetime updates | Same promise |

---

## Summary: what the inventory shows

- This inventory has **219 feature rows** across 20 areas. They expand to
  several hundred individual settings (Brush Studio alone has 100+, and there
  are 25+ blend modes). Most of them are for painting: brush engine internals,
  pixel filters, blend modes, masks, 3D and animation. None of these matter
  for making a logo.
- Doodlemark v1 covers **~70 of those rows** in some form, mostly simplified
  or handled by Apple's built-in components, and adds **4 things
  Procreate doesn't have**: SVG export, logo starter prompts, palette-wide
  recolor, and mockup previews. Text on a curve and radial symmetry badges
  come in v1.1.
- The **v1.1 priority list**, ranked by value for logos:
  QuickShape-style snapping → time-lapse export → radial symmetry → text on a
  curve → Palette Capture → brand kit export → lasso on Ink → eyedropper.
