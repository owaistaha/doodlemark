# Device checklist

Things the simulator can't prove. Run them on a physical iPad, with a finger
first, then with an Apple Pencil or stylus if you have one. Tick the box
when the result matches. If it doesn't, write what happened under the item
and open it in `RISKS.md`.

Every bootstrap step adds its device-only checks here.

Setup: build the Debug scheme onto the iPad (see CLAUDE.md "Before you
start"), turn off Pencil only unless an item says otherwise, start with a
blank canvas at 100%.

## Step 4: canvas, undo, Mirror, Grid, Smooth my lines

1. [ ] **Second finger mid-stroke.** With Ink, start a line with one finger;
   while it's still moving, put a second finger down and pinch.
   *Expected:* the half-drawn line disappears, the canvas zooms, and nothing
   is undone (the line count before the stroke is unchanged).
2. [ ] **Two-finger pan.** Zoom in to about 200%, then drag with two fingers
   without pinching.
   *Expected:* the canvas moves, all layers stay lined up, no stray line or
   dot is drawn, nothing is undone.
3. [ ] **Two-finger tap = undo, three-finger tap = redo.** Draw three lines.
   Tap the canvas with two fingers, twice. Then tap with three fingers once.
   *Expected:* two lines disappear one at a time, then one comes back. The
   Undo/Redo buttons in the top bar enable and disable to match.
4. [ ] **System undo gestures.** Draw two lines. Swipe left with three
   fingers, then swipe right with three fingers.
   *Expected:* the swipe left undoes one line and the swipe right brings it
   back (the iPadOS "Undo"/"Redo" banner appears). A three-finger pinch
   (copy/paste menu) doesn't undo anything.
5. [ ] **Keyboard undo.** With a hardware keyboard attached, draw two lines,
   press ⌘Z, then ⇧⌘Z.
   *Expected:* one line is undone, then redone. Holding ⌘ shows Undo/Redo in
   the shortcut overlay.
6. [ ] **Pencil line width (RISKS #9).** With an Apple Pencil (or stylus),
   Line size 16, draw a line on the debug "Export test" screen and read the
   status line.
   *Expected:* stored width 10.00 (tool width + 2), the same as a finger.
   Pressing harder or lighter doesn't change the line's thickness.
7. [ ] **Smooth my lines with a finger.** Smooth my lines on. Draw a slow,
   shaky circle and a zig-zag "W".
   *Expected:* the circle comes out visibly less wobbly. The W keeps its
   sharp points, and both ends of each line stay where your finger started
   and stopped. Turn it off and draw again: the line keeps the wobble.
8. [ ] **Mirror and undo.** Turn Mirror on. Draw a line on the left half.
   *Expected:* a mirrored copy appears on the right half as soon as you lift
   your finger, and the hint pill says "Mirror is on". One undo removes both
   halves.
9. [ ] **Grid and Mirror toggles.** Tap Grid, then Mirror, then both again.
   *Expected:* the grid and the dashed centre line appear and disappear. The
   hint pill only mentions Mirror while the Ink tool is selected.
10. [ ] **Pencil only and resting palm.** Turn Pencil only on. Rest your
    palm on the canvas and draw with the Pencil.
    *Expected:* only the Pencil draws, the palm leaves no marks. A finger
    alone doesn't draw (but two fingers still pan and zoom).
11. [ ] **Export in Safari (step 3 gate, by hand).** On the debug "Export
    test" screen (a bare Ink canvas: no smoothing, no Mirror), draw a few
    lines with a finger (curves, a zig-zag, a dot), tap Export SVG, and open
    the file in Safari (AirDrop it to a Mac or use Files). Repeat with a
    Pencil or stylus.
    *Expected:* the SVG looks the same as the canvas: same lines, same
    thickness, nothing missing or shifted. (Smoothed and mirrored lines get
    the same check through the real export in step 7; the unit-test gate
    already covers them.)

## Step 5a: palette

12. [ ] **Tap and hold a swatch.** With a finger, press and hold the first
    palette color for about half a second.
    *Expected:* the system color picker opens in a popover next to the
    swatch, titled "Color 1". A quick tap (no hold) only selects the color
    (blue ring) and never opens the picker.
13. [ ] **Live recolor while dragging.** Draw two Ink lines in color 1 and
    one in color 2. Hold color 1, switch to Spectrum and drag your finger
    across it.
    *Expected:* the color-1 lines and swatch follow your finger smoothly
    (no lag of more than a moment, no flicker); the color-2 line never
    changes. Tap outside the popover: it closes and one Undo puts color 1
    and its lines back.
14. [ ] **Eyedropper.** Hold a swatch, tap the eyedropper in the picker and
    pick a color from the canvas.
    *Expected:* the slot takes that color, like any other pick.
15. [ ] **Try another with a finger.** Tap Try another a few times.
    *Expected:* the swatches, the Shapes layer tile and every Ink line
    drawn in a palette color change together; each tap is one Undo.

## Step 5b: shapes

16. [ ] **Add and drag with a finger.** Shapes tool, tap Star, then drag the
    star around with one finger.
    *Expected:* the star appears in the middle in the selected color, with a
    blue box and four round handles. It follows your finger without lagging
    behind, and stops exactly where you lift.
17. [ ] **Snap to the middle.** Drag the star slowly back across the centre.
    *Expected:* near the middle it clicks onto the centre line(s) and orange
    guide lines appear; they disappear when you lift. Moving on past the
    centre pulls it off again without fighting you.
18. [ ] **Resize from a corner.** Drag any of the four handles in and out.
    *Expected:* the shape grows and shrinks around its centre, and the
    handle stays under your finger. Handles are easy to hit with a
    fingertip, also on a small shape.
19. [ ] **Two fingers on the shape.** Put two fingers on the picked shape,
    then pinch, spread and twist.
    *Expected:* the shape shrinks, grows and turns in 15° clicks; the canvas
    doesn't zoom. Lift one finger and put it back mid-gesture: the shape
    doesn't jump. One Undo takes back the whole gesture.
20. [ ] **Two fingers next to the shape.** Pinch on empty canvas away from
    the picked shape.
    *Expected:* the canvas zooms like before; the shape doesn't change.
21. [ ] **Pick, fill, flip, delete.** Add a circle and a triangle that
    overlap. Tap each; tap a swatch; use Flip upside down and Delete; tap
    empty canvas.
    *Expected:* a tap picks the shape under your finger (a tap between a
    star's arms picks the star); a swatch fills the picked shape; the
    triangle turns upside down; Delete removes it and Undo brings it back;
    tapping empty canvas un-picks.
22. [ ] **Pencil and shapes.** With Pencil only on, pick and drag a shape
    with a finger, then with the Pencil.
    *Expected:* both work: Pencil only is about drawing, not shapes.


## Step 5c: text

23. [ ] **Type with the on-screen keyboard.** Text tool, tap "Your logo
    name", type "Pizza Rocket" with no hardware keyboard attached.
    *Expected:* the keyboard slides up and the canvas shrinks to sit fully
    above it (no zoom or hint pill), with the whole logo visible. The top
    bar stays where it is. "Logo name" scrolls to the top of the panel, and
    the field and its "12/24" counter are above the keys. The name appears in
    the middle of the canvas as you type, in the selected color.
24. [ ] **Emoji and odd characters.** Still typing, open the emoji keyboard
    and tap 🍕, then try "★" or a Chinese character if you have that
    keyboard.
    *Expected:* nothing is added to the field or the canvas, and a short note
    "This font can't draw “🍕”." shows under the field, above the keyboard.
    No alert. Typing a normal letter makes the note go away.
25. [ ] **Scribble with the Pencil.** Hardware keyboard off. With the Apple
    Pencil, handwrite "Moon Cafe" straight into the name field (Settings →
    Apple Pencil → Scribble on).
    *Expected:* it turns into typed text in the field and on the canvas,
    exactly like typing, and one Undo takes the whole name away. Scribbling a
    smiley or a symbol the font lacks gives the same friendly note.
26. [ ] **Dictation.** Tap the microphone key and say "Star Club".
    *Expected:* the words land in the field and on the canvas. Dictated
    emoji ("smiley face") are left out with the note.
27. [ ] **Hardware keyboard.** Attach a keyboard (Magic Keyboard or
    Bluetooth), type a name, press Return, then ⌘Z.
    *Expected:* no on-screen keyboard and no canvas shrink. Return ends
    typing; ⌘Z takes back the whole name in one step, ⇧⌘Z brings it back.
28. [ ] **Undo while typing.** Type a name, then without leaving the field
    tap the toolbar's Undo. Then try the Undo arrow in the keyboard's
    shortcut bar on a second name.
    *Expected:* the toolbar Undo is enabled while typing and takes back
    everything typed since the field was tapped in one step. With the
    keyboard's Undo, the field and the canvas must always show the same text
    (note which one it does: whole name, or letter by letter in the field).
29. [ ] **Font picker.** Hide the keyboard and look at the Font list.
    *Expected:* each font name is written in its own font and easy to read
    at arm's length, Pacifico included. Tapping one changes the canvas
    text right away; the chosen row has the blue border and a check.
30. [ ] **Font that can't draw it.** Type "Kő" in Bungee (Hungarian ő; long
    press o on the keyboard), then tap Lilita One.
    *Expected:* the font stays Bungee, and the note says "Lilita One can't
    draw “ő”. Change the text first."
31. [ ] **Move, resize, turn the text with a finger.** Drag the text,
    drag a corner handle, then two fingers on the text to twist it.
    *Expected:* same feel as shapes: follows the finger, snaps to the
    centre lines with orange guides, turns in 15° clicks, one Undo per
    gesture. The blue box hugs the letters (not a big square), and no handle
    covers the first or last letter.
32. [ ] **Long name at the edge.** Type 24 characters, make it big and
    spread it with Letter spacing until it reaches the canvas edges.
    *Expected:* the 25th character is refused with "Up to 24 letters and
    spaces." All four handles stay fully visible inside the canvas and can
    still be grabbed.
33. [ ] **Letter spacing and ALL CAPS.** Drag the Letter spacing slider
    from one end to the other, then toggle ALL CAPS, in Pacifico and in
    Poppins.
    *Expected:* letters spread evenly and the word stays centred; one Undo
    per slider drag; ALL CAPS switches to capitals and back to exactly what
    you typed.
34. [ ] **Text export in Safari (do after step 7).** The debug Export test
    screen exports Ink only, so this waits for the real share-sheet export.
    Make a logo with a shape and the text (any font, turned, spaced), export
    the SVG, and open it in Safari on the iPad and on a Mac without these
    fonts installed. Until then the simulator gate covers it (all five fonts,
    turned and spaced, pass).
    *Expected:* the text looks identical to the canvas: same font, spacing,
    turn and color, nothing replaced by a system font.

## Step 6: saving, gallery, New logo

35. [ ] **First launch.** Delete the app, install it again and open it.
    *Expected:* it opens straight to the gallery (no splash): "No logos yet",
    a friendly line and a New logo button.
36. [ ] **The PRD check: force-quit.** New logo → a prompt → Start drawing.
    Sketch something, ink over it, add a shape and a name. Wait until the
    title says "Saved". Swipe up to the app switcher and swipe Doodlemark
    away. Open it again.
    *Expected:* the logo is in the gallery with its picture, named after the
    prompt, "Edited today". Opening it shows everything exactly as you left
    it: sketch, lines, shape, name, colors, Mirror and Grid.
37. [ ] **Force-quit right after drawing.** Draw one line and immediately go
    to the app switcher and swipe the app away (don't wait for "Saved").
    *Expected:* the line is still there after reopening (the app saves as
    it leaves the screen). Note it if it isn't.
38. [ ] **Back saves.** Draw, then tap Back at once.
    *Expected:* the gallery card's picture already shows the new line.
39. [ ] **Untouched new logo.** New logo → Start drawing → Back without
    drawing.
    *Expected:* no empty "Untitled logo" card appears.
40. [ ] **Rename, duplicate, delete.** Touch and hold a card with a finger.
    Rename it (keyboard comes up in the box), then Duplicate, then Delete
    the copy.
    *Expected:* the menu appears under your finger; the new name shows on
    the card; the copy appears first as "<name> copy"; Delete asks first
    and only removes the copy. Also rename from the canvas by tapping the
    title.
41. [ ] **Gallery scrolling.** Make about 12 logos (Duplicate helps) and
    flick the gallery up and down fast.
    *Expected:* smooth scrolling, pictures appear without flashing, newest
    edited first.
42. [ ] **Sketch-only card.** Make a logo with only a Sketch doodle, go back.
    *Expected:* the card shows the doodle, faded (not a blank card). Add one
    Ink line: the card then shows only the ink, like the export.
43. [ ] **Low storage.** If you can, fill the iPad until it warns about
    storage, then draw.
    *Expected:* the title says "Couldn't save. Trying again on the next
    change." and nothing crashes; it saves again once there's space.
44. [ ] **New logo screen with a finger.** Tap Shuffle a few times, pick a
    prompt, tap it again, then pick another; also try a "Need an idea?" chip
    in the gallery.
    *Expected:* Shuffle visibly changes the grid; tapping the picked prompt
    again goes back to Blank canvas; "Selected:" follows; the chip opens a
    new logo named after it directly.
45. [ ] **Portrait.** Turn the iPad to portrait on the gallery and the New
    logo screen.
    *Expected:* the grid reflows to fewer columns, the chips move under the
    title, nothing is cut off or overlapping.
46. [ ] **Files app.** (Optional) The projects don't appear in the Files app
    (they're app data, not documents). (Since step 8, Settings → Doodlemark
    has one switch: "Show drawing tips again", see 60.)
    *Expected:* as described; note it if projects do show up in Files.
47. [ ] **Crash mid-save (folder swap).** Draw a few Ink lines, change the
    palette with "Try another", and within a second swipe up to the app
    switcher and force-quit. Repeat 5 times at slightly different moments.
    *Expected:* every time the logo opens, and every Ink line still follows
    its palette color (tap and hold a swatch, change it: the matching lines
    change too). Never an error card, never lines left in an old color.

## Step 7: Preview & export

48. [ ] **Nothing to export.** New logo, tap "Preview & export" straight
    away; then draw only on Sketch and tap it again.
    *Expected:* both times "Draw something first." with OK, and no export
    screen or share sheet.
49. [ ] **Mockups.** Make a logo with a shape, Ink and a name, tap "Preview &
    export".
    *Expected:* app icon, sticker, tiny test and light & dark all show your
    real logo (not the sketch), sharp on the Retina screen; the 16 pt one is
    tiny but crisp.
50. [ ] **AirDrop.** Export & share → AirDrop to a Mac or iPhone.
    *Expected:* both files arrive with the name from the field
    (`pizza-rocket.svg`, `pizza-rocket.png`).
51. [ ] **Save to Files.** Export & share → Save to Files → On My iPad.
    *Expected:* the SVG and PNG are there and open in Files' preview.
52. [ ] **Save Image to Photos.** Untick SVG, keep PNG, Export & share →
    Save Image.
    *Expected:* the first time, iPadOS asks with "Doodlemark saves your logo
    picture to your photos when you tap Save Image. It never looks at your
    other photos." Allow: the 1024 × 1024 picture is in Photos (transparent
    shows on the Photos background). Don't allow: no crash, just no picture.
53. [ ] **Open the SVG in Safari.** Open the saved SVG in Safari (Files →
    share → Safari, or AirDrop it to a Mac).
    *Expected:* it looks the same as the canvas: same shapes, lines, text
    and colors, nothing missing or shifted, and no sketch.
54. [ ] **Open the SVG in Figma** (or Illustrator/Inkscape, if you have one).
    *Expected:* it imports as vector paths (text is outlines, so it looks
    right without the font), three groups: shapes, ink, text.
55. [ ] **Transparent vs paper.** Export the PNG twice, with and without
    Transparent background, and open both in Photos or on a dark Mac
    Preview background.
    *Expected:* one has see-through corners, the other a cream (#FBF8F2)
    square behind the logo.
56. [ ] **File name.** Type "Space Cat/2!" into File name.
    *Expected:* the line under it says "Saves Space-Cat-2.svg and
    Space-Cat-2.png", and the shared files have exactly those names.
57. [ ] **Back to drawing.** Tap "Back to drawing" after sharing.
    *Expected:* the canvas is exactly as it was (same tool, layers, zoom),
    and the gallery card is up to date.

## Step 8: first-canvas tips

58. [ ] **First canvas.** Delete and reinstall the app, tap New logo → Start
    drawing.
    *Expected:* "Sketch it messy first" points at the Sketch tool, then
    "Then trace it clean" at Ink, then "Show it to the world" at Preview &
    export. The ring sits right around each control in landscape and
    portrait. A finger on the dimmed canvas draws nothing.
59. [ ] **Shown once, Skip.** Open another logo; reinstall and tap "Skip
    tips" on the first tip.
    *Expected:* no tips on the second canvas; Skip ends them for good.
60. [ ] **Show again.** Settings → Doodlemark → turn on "Show drawing tips
    again", go back to the app, open a logo.
    *Expected:* the tips show again once, and the switch is off again in
    Settings afterwards.
61. [ ] **VoiceOver.** With VoiceOver on, open the first canvas.
    *Expected:* it reads "Tip 1 of 3. Sketch it messy first", the body,
    and the Got it / Skip tips buttons; the canvas behind isn't reachable.

## Step 8b (part 1): scoring thresholds

62. [ ] **Finger calibration (needs the lesson player, 8b part 2).** Trace
    each lesson's steps with a finger: once carefully, once at normal
    speed, once fast and sloppy. Note the stars and the tip each time.
    *Expected:* careful = 3 stars, normal = mostly 2–3 and never "Almost!
    Try once more", sloppy = 0–2. If a careful finger gets the wobble tip,
    raise `ScoringConfig.wobbleLimit` (now 0.25); if sloppy lines get 3
    stars, lower the distance thresholds. The simulator check is in
    `DoodlemarkTests/GateOutput/learn-calibration.txt`.
