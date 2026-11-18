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
- Top bar 72 pt: back, title + "Saved", undo/redo, Mirror and Grid toggles, primary "Preview & export".
- Left tool rail 100 pt: Sketch, Ink, Shapes, Text, Eraser (icon + label, never icon only).
- Right panel 300 pt: Layers (fixed 4, active one highlighted), Palette (3 swatches + "Try another"), tool options ("Line size", "Smooth my lines", "Pencil only").
- "Line size" is a slider over the **line's real thickness** on the canvas
  (4–40, steps of 2, default 16). Never show PencilKit's internal width;
  `LineSize` converts (see TECH_SPEC "Line size").
- Canvas: centered square on `canvasBackdrop`, with a floating dark hint pill at the bottom for the current mode.

## Voice
Friendly words over jargon: "Smooth my lines", not "stroke stabilization";
"Mirror", not "symmetry guide"; "Your sketch layer stays private. It's never
exported." Short sentences and no exclamation-mark spam.

## Icons
SF Symbols in the app (line style, regular weight) to match the stroke icons
in the mockups. No emoji in the UI.
