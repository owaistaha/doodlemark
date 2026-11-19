# DESIGN.md — Doodlemark visual system

Source of truth for `Theme.swift`. The screens live on the design canvas
"Doodlemark — iPad app design" (Gallery, New logo, Canvas, Preview & export,
Style guide), drawn at iPad landscape 1194×834 pt.

## Direction
Playful enough for a 10-year-old, clean enough for a founder. Warm paper
background, ink-black text, one loud action color (tangerine), and one
"selected / on" color (blue). The UI stays calm so the user's logo is the most
colorful thing on screen. Surfaces are flat paper and white, with no Liquid
Glass styling (no glass materials), even on iPadOS 26.

## Color tokens
| Token | Hex | Use |
|---|---|---|
| `paper` | #FBF8F2 | App background |
| `surface` | #FFFFFF | Cards, panels, top bar, tool rail |
| `canvasBackdrop` | #EFEAE0 | Area around the drawing square |
| `thumbBackdrop` | #F3EFE7 | Gallery thumbnail backgrounds, empty tiles |
| `ink` | #1C1B22 | Text, icons, ink strokes |
| `inkMuted` | #5E5B66 | Secondary text (passes 4.5:1 on paper and white) |
| `line` | #E7E2D8 | Borders, dividers |
| `lineStrong` | #CFC8BA | Dashed "new" tiles, text field borders |
| `tangerine` | #FF5A1F | Primary buttons, main action. **Text on it is always `ink`** (white fails contrast) |
| `pencilBlue` | #2F5BFF | Selected tool, toggles that are on, active layer, focus rings. White text OK |
| `blueTint` | #EEF2FF | Background of selected rows/cards (with a 2pt `pencilBlue` border) |
| `blueText` | #3A4CB8 | Secondary text on `blueTint` |
| `butter` | #FFC93C | Small highlights only (hint dot, logo accents) |
| `sketchStroke` | #C9C3D3 | Sketch-layer pencil color (faded look) |

Selection must never rely on color alone. Selected items also get a ring, a
thicker border or a weight change.

## Type
- **Display:** Bricolage Grotesque 800 (OFL, bundle the static 800 instance, not the variable file). Sizes: display 44–48, title 28, heading 20–24.
- **UI/body:** Inter 400/600/700 (OFL, bundle the static instances, not the variable file). Body 17, labels 15, small 13, section labels 13 semibold, uppercase, +0.6 tracking.
- Both fonts are UI fonts only. Logo text uses the separate bundled logo-font set (see CLAUDE.md).

## Shape, spacing, touch
- 8 pt grid. Screen padding 48 (gallery) / 20 (editor bars).
- Radii: 8 icon tiles and checkboxes · 12 small controls · 14–16 buttons · 20 cards and tools · 24–28 big panels and the canvas.
- Touch targets ≥ 44 pt everywhere. Tool rail buttons are 76×76 pt. Primary buttons are 52–56 pt tall.
- Shadows only on the canvas square and mockups: `0 12 40 ink@10%`.

## Layout (editor)
- Top bar 72 pt: back (to the gallery, saves first), project name + save
  state ("Not saved yet", "Saving…", "Saved", "Couldn't save…"; tap the name
  to rename), undo/redo, Mirror and Grid toggles, primary "Preview & export".
- Left tool rail 100 pt: Sketch, Ink, Shapes, Text, Eraser (icon + label, never icon only).
- Right panel 300 pt: Layers (fixed 4, active one highlighted), Palette (3 swatches + "Try another"), tool options ("Line size", "Smooth my lines", "Pencil only").
- Palette: tap a swatch to make it the current color (blue ring); tap and
  hold opens the system color picker next to it. Caption under the swatches:
  "Tap and hold a color to change it everywhere." "Try another" is a compact
  Secondary button (white, 1 pt `line` border, 44 pt touch target).
- "Line size" is a slider over the **line's real thickness** on the canvas
  (4–40, steps of 2, default 16). Never show PencilKit's internal width;
  `LineSize` converts (see TECH_SPEC "Line size").
- Canvas: centered square on `canvasBackdrop`, with a floating dark hint pill at the bottom for the current mode.
- Shapes tool panel: "Picked shape" (Flip sideways, Flip upside down, Delete as
  full-width Secondary buttons) first when a shape is picked, then "Add a
  shape": a 2 × 2 grid of 76 pt tiles showing each shape in the current color
  with its name.
- Picked shape or text on the canvas: a 2 pt `pencilBlue` box 15 pt outside
  its outline's bounds with four 26 pt white handles ringed in `pencilBlue` on
  the box corners (64 pt touch target), so no handle covers the drawing. At
  the canvas edge the handles are pulled in to stay whole and grabbable.
  Snap guides: 2 pt `tangerine` lines through the canvas centre, only while a
  moved item is snapped. All drawn at the same size at any zoom.
- Text tool panel: "Logo name" (a text field, 44 pt, 12 pt radius, 1 pt
  `lineStrong` border, 2 pt `pencilBlue` while typing; placeholder "Your logo
  name"), under it a one-line note in `small` `ink` when a character is left
  out ("This font can't draw “😀”.", never an alert) and an "n/24" counter in
  `inkMuted`. Then "Font": one row per logo font, its **name written in that
  font** (26 pt) with the style word under it ("Bubbly", "Blocky", "Rounded",
  "Script", "Clean"); chosen = `blueTint`, 2 pt `pencilBlue` border and a
  check. Then "Size" and "Letter spacing" sliders with their values, the
  "ALL CAPS" checkbox row and a full-width "Delete text" Secondary button,
  all disabled until there's text.
- With the on-screen keyboard up, the canvas square shrinks to fit above it
  (12 pt margins, zoom and hint pills hidden), the tool rail stays put behind
  the keys, and the panel scrolls "Logo name" to its top so the field and its
  note are always visible.

## Layout (gallery, design/Gallery.png)
- Paper background, 48 pt padding. Header: the app mark (ink tile with a
  tangerine squiggle) + "Doodlemark" (Bricolage 30); the "My logos | Learn"
  switch (white, 1 pt border; selected = `pencilBlue` with white bold text);
  "New logo" primary button (56 pt). No settings button in v1 (the mockup's
  sun icon has no feature behind it; the app is light-only).
- "Your logos" (display 44) and "Doodle it. Ink it. Export it."; "Need an
  idea?" with the first three prompts as white capsule chips (to the right of
  the title when they fit, under it when they don't). A chip starts a new logo
  with that prompt straight away.
- Cards grid (adaptive, ≥ 230 pt columns, 24 pt gaps): "Start a new logo"
  dashed tile first (2 pt `lineStrong` dashes, 76 pt tangerine plus tile),
  then projects, newest edited first: white card, 20 pt radius, 1 pt `line`
  border; the thumbnail on `thumbBackdrop` (168 pt), then the name (Inter
  bold 20) and "Edited today / yesterday / 3 days ago / last week / 2 weeks
  ago" in `inkMuted`. Touch and hold for Rename, Duplicate, Delete; Delete
  asks first ("It's gone for good. This can't be undone.").
- A project that can't be read: same card with a warning symbol, "Couldn't
  open this logo", "Its file is damaged." and a Delete button.
- First launch: one dashed card with the app mark, "No logos yet", "Every
  logo starts with a doodle. Tap New logo to make your first one." and
  "New logo".
- Learn tab (until step 8b): graduation cap in a `blueTint` circle, "Lessons
  are coming soon".

## Layout (New logo, design/NewLogo.png)
- "‹ Gallery" (white, 56 pt), "Pick a start" on the right; "What are we
  making today?" (display) and the subtitle.
- Left: the Blank canvas card (300 pt). Right: "Or try a prompt", Shuffle,
  a 3 × 3 grid of prompt cards (56 pt colored square + title, 104 pt tall).
  Selected (blank or a prompt) = `blueTint` + 2 pt `pencilBlue` border.
  Blank is selected when the screen opens; tapping a selected prompt goes
  back to blank. "Selected: …" and "Start drawing →" at the bottom.
- 10 prompts, 9 shown; Shuffle always brings in the hidden one.

## Layout (Preview & export, design/Export.png)
- Opens full screen over the canvas. Top bar: "‹ Back to drawing" (white,
  56 pt) and "Preview & export" (heading).
- Left, on `paper`: "<Name>, out in the world" (display) and "A good logo
  works big, tiny, light and dark. Check yours here." Then a 2 × 2 grid of
  mockup cards (radius 28, 262 pt tall, 32 pt screen padding so all four fit
  in landscape): App icon (white card, the logo on
  paper in a 150 pt rounded tile with the mockup shadow), Sticker
  (`pencilBlue` card, white-rimmed 170 pt circle, white caption), Tiny test
  (96 · 48 · 24 · 16 pt, "Can you still tell what it is?"), Light & dark
  (paper and ink halves, caption strip).
- Right panel (400 pt, white): "Export" (title), the SVG card ("Vector"
  badge in `pencilBlue`) and the PNG · 1024 × 1024 card. On = `blueTint`
  with a 2 pt `pencilBlue` border and a blue checkbox; off = white with a
  hairline. Transparent background row with a checkbox (faded when PNG is
  off). File name field on `paper` (56 pt) and a small line showing the
  cleaned name. "Export & share" (tangerine, 56 pt) at the bottom, and
  "Your sketch layer stays private. It's never exported." under it.
- Nothing to export: an alert "Draw something first." ("Ink a line, add a
  shape or type a name. Your sketch stays private, so it doesn't count.").

## Voice
Friendly words over jargon: "Smooth my lines", not "stroke stabilization";
"Mirror", not "symmetry guide"; "Your sketch layer stays private. It's never
exported." Short sentences and no exclamation-mark spam.

## Icons
SF Symbols in the app (line style, regular weight) to match the stroke icons
in the mockups. No emoji in the UI.
