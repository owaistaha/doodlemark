# Procreate teardown → what Doodlemark should (and shouldn't) copy

> **Background research only.** "v1" marks here don't add scope. Scope comes
> from PRD.md (source-of-truth order: PRD > CLAUDE > DESIGN > TECH_SPEC).

Reference: Procreate 5.4.x for iPad (latest 5.4.14, Sep 2026), by Savage Interactive.
Price: **$12.99 one-time**, no free tier, no trial. Siblings: Procreate Pocket
(iPhone, $5.99) and Procreate Dreams (animation, $19.99). Each one is a separate purchase.

---

## 1. Procreate's feature map (summary)

> The full, section-by-section list of every feature with a v1/v1.1/skip
> verdict is in **`PROCREATE_FEATURE_INVENTORY.md`**.

| Area | What Procreate has | Doodlemark v1? |
|---|---|---|
| **Engine** | Custom Metal engine ("Valkyrie"), very high-res canvases, 120Hz low latency | ❌ Use PencilKit (Apple's engine). Fast enough for this, and free |
| **Brushes** | Big new brush library in 5.4, a "Classic" library, Brush Studio with 100+ settings per brush, Photoshop .abr import | ⚠️ Only 3–4 brushes: pencil (sketch), monoline pen (ink), marker, eraser |
| **Layers** | Layers, groups, blend modes, opacity, Alpha Lock, clipping masks, layer masks. Layer count is limited by canvas size and RAM | ⚠️ A **fixed** 4-layer stack (Sketch / Shapes / Ink / Text). No free layer management in v1 |
| **Selection** | Automatic, freehand, rectangle, ellipse, feather, save/load selections | ❌ Tap an object to select it (shapes/text only) |
| **Transform** | Freeform, uniform, distort, warp, advanced mesh warp, nudge, snapping | ⚠️ Move/scale/rotate for shapes and text, with snapping to centre |
| **Adjustments** | HSB, curves, color balance, gradient map, blurs, noise, sharpen, bloom, glitch, halftone, chromatic aberration, liquify, clone, Pencil Filters | ❌ Not logo tools. Skip all of them |
| **Color** | Disc, classic, harmony, value, palettes, palette capture from camera, color history, ColorDrop fill | ✅ Simplified: **pick a 3-color palette** from curated sets, plus a custom picker |
| **Drawing aids** | QuickShape (hold to snap a line/circle), StreamLine/stabilisation, Motion Filtering, drawing guides (grid, isometric, perspective, symmetry), Drawing Assist | ✅ Grid and **symmetry** guide (symmetry is very logo-useful). Shape snap is v1.1 |
| **Text** | Text tool, font import | ✅ Logo name with 4–6 bundled free (OFL) fonts |
| **Animation** | Animation Assist (frames, onion skins, GIF/MP4) | ❌ Out of scope |
| **3D / AR** | 3D model painting (OBJ/USDZ), AR preview, FacePaint | ❌ Out of scope |
| **Time-lapse** | Records every stroke, replay, 4K export, 30-second social clip | 🟡 v1.1. Great for kids and TikTok sharing, but not core |
| **Reference** | Reference Companion window (image or canvas preview) | ✅ Sketch layer can hold an imported reference photo |
| **Gestures** | Two-finger tap undo, three-finger redo, pinch zoom/rotate, QuickMenu, eyedropper hold | ✅ Undo/redo taps and pinch zoom (people expect these) |
| **Gallery** | Grid of artworks, stacks, drag to reorder, previews | ✅ Simple project grid |
| **Export** | .procreate, PSD, PDF, JPEG, PNG, TIFF, GIF, MP4, OBJ, USDZ | ✅ **SVG** (Procreate can't do this) and transparent PNG |
| **UI** | Minimal "canvas-first" UI, refreshed for iPadOS 26 in 5.4.5 | ✅ Same canvas-first idea, but friendlier and bigger targets |

## 2. Why Procreate is a bad logo tool (your opening)

1. **It's all pixels.** There's no SVG and no real vector output. A logo made in
   Procreate gets blurry when you scale it up, and you have to trace it again in
   Illustrator, Figma or Vectornator/Linearity.
2. **It starts from a blank canvas.** There are no logo prompts, templates,
   palettes or "what makes a good logo" guidance. That's hard for a 10-year-old
   or a first-time founder.
3. **No brand output.** You get a picture, not a mini brand kit (logo, colors,
   font name, icon versions).
4. **No free trial.** You pay $12.99 before you can try it. A free first logo is
   an easy way to win against it.
5. **It's built for illustrators.** Brush Studio with 100+ settings is power,
   but for this audience it's noise.

## 3. Positioning in one line

> **Procreate is for painting pictures. Doodlemark turns a doodle into a real logo.**
> You sketch freely, ink it clean, add your name and colors, and export an SVG
> you can actually use.

## 4. What to copy from Procreate's playbook

- **Canvas first:** the drawing takes almost the whole screen, and tools stay small at the edges.
- **Gesture undo** (two-finger tap). Kids pick it up right away.
- **One-time-price trust:** people love Procreate for having no subscription.
  If Doodlemark ever charges, a one-time "Pro unlock" fits this market better
  than a subscription (decide later; see PRD "out of scope").
- **Time-lapse as free marketing:** every shared replay advertises the app. That's the first v1.1 feature.
