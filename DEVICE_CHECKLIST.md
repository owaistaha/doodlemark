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

