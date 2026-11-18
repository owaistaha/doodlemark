# Doodlemark — PRD (v1 / weekend MVP)

*(Working title. Check the App Store, domain and social handles before you commit.)*

## One-liner
An iPad app where you doodle an idea with your finger, any stylus or an Apple Pencil, ink it clean on top,
add your name and colors, and export a real vector logo (SVG + PNG). It works
for a 10-year-old making a logo for their YouTube channel, and for a
first-time founder who can't afford a designer.

## Problem
Making a logo today means either a pro vector tool (Illustrator, Figma), which is
intimidating and not made for sketching, or a drawing app like Procreate, which
feels great to sketch in but only outputs pixels, starts from a blank page and
costs $12.99 upfront. Kids and young pros have ideas they can doodle in 30
seconds, but nothing turns that doodle into something they can put on a profile,
a sticker or a website. (Full competitor breakdown: `PROCREATE_TEARDOWN.md`.)

## Target user
- **Primary:** Creative kids (8–14) and teens making logos for a YouTube
  channel, gaming clan, school club or pretend company
- **Secondary:** Young professionals and student founders who need a first
  logo for a side project and have an iPad (no Apple Pencil needed)

Both groups want the same thing in v1: **fun, quick, and a usable file at the
end.** The UI is playful but not babyish (big targets, friendly copy, no clutter).

## Core loop
1. **Start:** tap "New logo". Pick a blank canvas or a fun prompt card
   ("A logo for a pizza rocket company").
2. **Sketch:** doodle freely with the pencil on the faded Sketch layer. It's
   messy on purpose, and it never gets exported as vector.
3. **Ink it:** switch to Ink and trace clean lines over the sketch with a
   constant-width pen. Add filled shapes (circle, square, triangle, star) and
   your name in a logo font. A symmetry guide is optional.
4. **Color:** pick a 3-color palette from curated sets (or custom).
5. **Show it off:** preview the logo on an app-icon tile and a round sticker,
   then export **SVG + transparent PNG** with the share sheet.

## Learn mode (core loop B)
Step-by-step trace lessons that teach sketching through logo-making:
1. Open the **Learn** tab and pick a lesson card ("Rocket in 5 strokes").
2. A faded ghost of the next stroke appears, with a start dot and a direction
   arrow. One short tip explains why ("Logos use simple shapes").
3. Trace it with a finger or stylus. You get **1–3 stars** and a friendly tip
   ("A little wobbly, try going slower"). You can redo it or move on.
4. After the last stroke, a summary shows the total stars and a
   **"Make it yours"** button that turns the drawing into a normal logo project
   (traced strokes go on the Ink layer, the palette is pre-picked, and you
   continue at core-loop step 4).

- [ ] Project gallery (grid of saved logos, new / open / delete)
- [ ] Square canvas with 4 fixed layers: **Sketch** (pencil, faded, hide
      toggle) → **Shapes** → **Ink** (monoline pen) → **Text**
- [ ] **Draw with anything:** finger, any capacitive stylus (cheap rubber-tip pens),
      Logitech Crayon or Apple Pencil. One finger draws; two fingers pan/zoom;
      two-finger tap undo, three-finger tap redo
- [ ] A "Pencil only" toggle (off by default) for Apple Pencil users who rest
      their palm on the screen
- [ ] Vector eraser on the Ink layer (it removes whole strokes; see TECH_SPEC for why)
- [ ] Shapes: circle, rounded square, triangle, star. Fill color, then move/scale/rotate
- [ ] Text: one logo-name text object, 4–6 bundled free (OFL) fonts, color, move/scale
- [ ] Guides: grid toggle and vertical symmetry (mirror) toggle for Ink
- [ ] Palette picker: ~12 curated 3-color palettes plus a custom color picker
- [ ] Mockup preview: app-icon tile and round sticker
- [ ] Export: **SVG** (Shapes + Ink + Text as real vector paths, text converted
      to outlines) and **transparent PNG** (1024px), shared via the share sheet
- [ ] Autosave; projects persist across force-quit and relaunch
- [ ] 10 starter prompt cards on the New screen
- [ ] **Learn tab** next to "My logos" with **5 lessons** (4–8 strokes each),
      ordered easy → harder, with a lock-free list (any lesson can be opened)
- [ ] Lesson player: ghost stroke + start dot + direction arrow, one tip per
      step, stroke scoring (1–3 stars + tip text), Redo / Next, progress dots
- [ ] Lesson complete screen: total stars, "Make it yours" → new project
- [ ] Stars per lesson saved locally (best score shown on the lesson card)
- [ ] Fully offline: no account, no network, no analytics (keeps the kids side simple)

## Explicitly out of scope for v1
- **AI feedback on drawings.** It needs a server, costs money, and would send
  kids' drawings off the device. Learn mode scoring is local maths only.
- **Warm-up drills and the daily challenge.** Good v1.1 add-ons (drills make a
  30-second warm-up before lessons; the daily challenge brings people back).
- **A lesson editor / user-made lessons.** v1 lessons are hand-authored JSON in the bundle.
- **Streaks, XP, badges, leaderboards.** Stars per lesson are enough. Streak
  pressure isn't a good fit for kids.
- **Free layer management, blend modes, masks.** The fixed 4-layer stack is
  what keeps this simple enough for kids and buildable in a weekend.
- **Hold-to-snap shapes (QuickShape-style).** PencilKit has no public shape
  recognition, so it would need custom stroke fitting. That's v1.1.
- **Auto-vectorise / trace the sketch.** Bitmap-to-vector tracing is a project on its own.
- **AI logo generation or "AI improve my doodle".** It needs a backend, costs
  money, and makes things harder for kids (data and consent). It also goes
  against the "you made this" spirit of v1.
- **Time-lapse replay/export.** The best v1.1 feature (free marketing), but not core.
- **Brand kit export** (PDF with colors and font names, multiple sizes). v1.1.
- **Pressure-sensitive (variable-width) ink in SVG.** It needs stroke-outline
  geometry. v1 ink is constant width on purpose (see TECH_SPEC).
- **Accounts, cloud sync, sharing gallery, community.** These need moderation,
  and that's a big deal with kids as users.
- **Monetization.** Decide after testing. A one-time Pro unlock fits this
  market better than a subscription (see teardown).
- **Pressure/tilt features.** Only Apple Pencil reports pressure, and fingers
  never do. Nothing in v1 depends on pressure, so every input works the same.
- **iPhone, Mac, Android.** iPad only (any iPad on iPadOS 17+).
- **Splash screen / long onboarding.** The app opens straight to the gallery,
  with one 3-step tip overlay on the first canvas.

## CV showcase requirements (this is a portfolio project)
- [ ] Public GitHub repo with a README: GIF of doodle → SVG, feature list,
      architecture diagram, "how the SVG exporter works" section, run steps
- [ ] Clean architecture: models / canvas / export / storage separated, no
      logic inside views beyond UI state
- [ ] Unit tests: SVG exporter (pixel-diff gate), shape geometry, symmetry
      mirroring, project save/load round-trip
- [ ] GitHub Actions CI: build + test on an iPad simulator on every push
- [ ] A 30–60s screen-recorded demo video for LinkedIn/portfolio
- [ ] Notes in the README on decisions and trade-offs (why monoline ink, why
      no backend, why native over Flutter). Interviewers ask about these

Note: running on your own iPad works with a free Apple ID. TestFlight and the
App Store need the paid Apple Developer Program ($99/year), so for a CV, the
GitHub repo + demo video is enough. Publishing is optional.

## Success metric for Learn mode
A first-time user (ideally a kid) finishes one lesson using only a finger,
gets a star score for every stroke, taps "Make it yours", and ends up on the
canvas with their traced drawing on the Ink layer, ready to color and export.

## Success metric
On a physical iPad, using a finger (and an Apple Pencil or stylus if one is
available), someone who has never seen the app
sketches a logo, inks it, adds a name and a palette, and exports an SVG.
Opened in Safari, the SVG looks the same as the canvas (same shapes, lines,
text and colors, nothing missing or shifted). The project is still in the
gallery after a force-quit and relaunch.
