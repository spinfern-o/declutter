# Organize shows your own photo, tidied

Status: the direction (your photo as the backdrop, the items' cutouts rearranged) and the faded photo were
chosen in chat on 2026-11-15. Everything under "My calls" is proposed and not yet approved. Nothing is built.
This file is both the spec and the plan.

## Intent
- Tapping "Organize" on a cabinet shows the photo you took, with every item lifted out and set back down
  neatly on the shelf the plan gives it, grouped by zone. It should read as "my cabinet, tidied", not as a
  drawing of a cabinet.
- Today Organize opens a 3D scene: plain boards and gray blocks on a white background. It does not look like
  your cabinet, and you said it should not be like this.
- You can still drag one item to another shelf, and everything that follows from that keeps working.

## What exists today that this uses
- `Space.photo`: the photo. `Item.cutout`: the item cut out of it, a PNG with a transparent background.
  `Item.box`: where the item sat, `[x, y, w, h]` as fractions of the photo. `Space.slotRects`: each shelf's
  rectangle on the photo, the same fractions. Nothing new is saved and the server is not touched.
- `CabinetLayout.rects(slots:saved:)` gives every shelf a rectangle, including shelves typed in by hand.
  `CabinetLayout.slot(at:in:heightRatio:)` finds the shelf under a drop point.
  `Space.shelf(of:)` and `Space.place(_:in:)` are the rules for one item on its own shelf.
- `CabinetSceneView` (the 3D screen) holds the parts to carry over as they are: the "Set Up Cabinet" prompt,
  the Plan button, `replan()` on appear and when shelves change, the haptic on a move, and the VoiceOver
  summary and "Move <item> to <shelf>" actions.
- `RoomView.cabinet` draws cabinets in the room in 3D with `CabinetLayout.footprints`. It stays.

## Approaches
- **A1, fade the photo (chosen).** The photo is drawn pale, the cutouts at full strength on top. The old
  items are still faintly there, the tidy ones stand out. App work only.
- **A2, erase the items from the photo (later).** The server fills in the holes where items were, so the
  backdrop is an empty cabinet. This is the real "tidied photo", but it needs a fill-in model on the server
  and a new saved image per cabinet. It is the named upgrade to A1, not part of this spec.
- **Keep the 3D scene and paste the photo behind it (dropped).** 3D boards and blocks in front of a flat
  photo never line up with the real shelves once the view is turned.

## Decided (your answers)
- The backdrop is your original photo.
- The end result should look like the photo, tidied. Items are their own cutouts, not blocks.
- Fade the photo now (A1). Erasing the items (A2) comes later.

## My calls (check these; each is a line to change, not a rebuild)
- **A flat screen, not 3D.** The photo is flat, so the screen is a plain SwiftUI picture with the cutouts
  placed on it. No orbiting. This also keeps this screen clear of the two 3D redraw bugs still open in the
  room view.
- **It replaces the 3D cabinet screen.** `CabinetSceneView.swift` is deleted and Organize opens the new
  screen. The room stays 3D. If you want to keep the 3D cabinet behind a button, say so.
- **How items are lined up.** On each shelf: left to right along the shelf's floor, bottoms on the floor,
  one zone after another, bigger items first inside a zone, a small gap between items and a wider one
  between zones, the whole row centered on the shelf. This is the same order the room's 3D cabinets use.
- **Size.** Each cutout is drawn at the size it had in the photo. If a shelf's row is too wide, or an item
  is taller than the shelf, that shelf's items all shrink by one shared factor. Nothing is ever enlarged.
- **Fade.** A white layer at 55% over the photo. One number in the code.
- **Toss items are not drawn**, as today: they are leaving the cabinet.
- **An item with no cutout** (added by hand) is a gray rounded tile with its name. An item with no saved
  position gets the tile size `CabinetLayout.defaultSide`.
- **Screen title:** "Organized".

## Non-goals
- Erasing items from the photo (A2), and anything on the server.
- Correcting for a cabinet photographed at an angle. Shelf rectangles are upright boxes, so on a tilted
  cabinet the row sits level while the shelf does not.
- Shadows, blending the cutouts into the shelf's light, cleaner cutout edges. Edges are as good as the
  model's outlines.
- A before and after switch, dropping an item at an exact spot, pinch to zoom.
- The room view and the spot sheet's preview. They stay 3D.

## Global constraints
- No unrequested UI polish. Rules go in `Logic/` as pure functions with a `selfCheck()` of asserts; write the
  failing assert first.
- No new SwiftData fields.
- This screen is only for a cabinet the user photographed (`productURL == nil`); marketplace furniture has
  no photo and must never reach it.
- `Organizer.tossZone` is the zone left out.
- Check: `frontend/scripts/selfcheck.sh <SIMULATOR_UDID>` must print `self-checks passed`.
- Commit messages are one short sentence saying what changed for the person using the app.

### Task 1: where each cutout goes (`Logic/CabinetLayout.swift`)
Add, next to `footprints`:

```swift
/// Each item's rectangle on the photo, standing on its shelf's floor: layout space (photo widths, y down).
static func tidy<ID: Hashable>(items: [(id: ID, slot: String, zone: String, name: String, box: [Double]?)],
                               rects: [String: [Double]], heightRatio: Double) -> [ID: CGRect]
static let gap = 0.01, zoneGap = 0.03  // photo widths: between items, and between zones
```

- An item's own size is `box[2]` wide and `box[3] * heightRatio` tall; with no box, `defaultSide` square.
- Order inside a shelf: zone, then larger first by `side(for:heightRatio:)`, then name. This is the sort
  `footprints` uses.
- One factor per shelf, at most 1, so the row with its gaps fits the shelf's width and the tallest item fits
  its height. Gaps are not scaled.

Write these asserts in `selfCheck()` first and see them fail. Shelf `"Top": [0.1, 0.1, 0.8, 0.3]`,
`heightRatio: 2` (so the shelf is 0.8 wide, 0.6 tall, floor at y = 0.8) unless a line says otherwise:
- one item, box `[0, 0, 0.2, 0.1]`: its rectangle is 0.2 wide and 0.2 tall. "an item keeps its photo size"
- the same item: `maxY == 0.8`. "items stand on the shelf's floor"
- the same item: `midX == 0.5`. "a row is centered on its shelf"
- three items `a` Tech, `b` Paper, `c` Tech, all the same box: `b` is left of both, and `a` and `c` are
  `gap` apart. "a zone's items stay together"
- with the same three: the space between `b` and the first Tech item is `zoneGap`. "zones are set apart"
- twelve items of box `[0, 0, 0.2, 0.1]`: all narrower than 0.2, all the same width, all inside the shelf,
  none overlapping. "a full shelf shrinks its items together"
- one item, box `[0, 0, 0.1, 0.5]` (1.0 tall, taller than the shelf): its height is 0.6 and its width 0.06.
  "an item taller than its shelf shrinks to fit, keeping its shape"
- one item with `box: nil`: `defaultSide` square. "an item with no saved position gets the default size"
- shelves `"Left": [0, 0, 0.5, 1]` and `"Right": [0.5, 0, 0.5, 1]`, two Tech items, one on each: the first
  ends at or before x = 0.5 and the second starts at or after it. "one item on another shelf leaves its
  zone where it was"
- an item whose `slot` has no rectangle is not in the result. "an item with no shelf is not drawn"

Expected: `selfcheck.sh` prints `self-checks passed`.

### Task 2: the tidied photo screen (`Features/Organize/TidyPhotoView.swift`, new)
`struct TidyPhotoView: View` with `@Bindable var space: Space`.

- The photo, scaled to fit the screen's width, with a white layer over it at `fade = 0.55`.
- `placed`: `space.items.byName`, without `Organizer.tossZone`, each with `space.shelf(of:)`; items with no
  shelf are left out. This is the list `CabinetSceneView` builds today.
- Each placed item is drawn at its `CabinetLayout.tidy` rectangle times the picture's drawn width: its
  cutout scaled to fit the rectangle, or the gray named tile when it has none.
- Dragging a cutout moves it with the finger. On release, the point just above its bottom middle goes to
  `CabinetLayout.slot(at:in:heightRatio:)`. A different shelf: `space.place(item, in:)` and the haptic.
  The same shelf or no shelf: it goes back where it was.
- Carried over from `CabinetSceneView` unchanged: the "Set Up Cabinet" prompt when there are no shelves, the
  Plan button, `replan()` on appear and when shelves change, the VoiceOver summary and "Move <item> to
  <shelf>" actions.
- `SpaceView.swift:77` opens `TidyPhotoView(space: space)`. Delete `Features/Cabinet3D/CabinetSceneView.swift`.
  `CabinetLayout.footprints`, `pack` and `depth` stay: the room uses them.
- `CLAUDE.md`, first paragraph: "Organize" shows the cabinet's photo tidied, not the cabinet in 3D.

Check in the Simulator, each with a screenshot:
- Organize on a cabinet with shelves shows the photo, pale, with the cutouts in rows on its shelves and each
  zone's items side by side. No cutout hangs outside its shelf's rectangle.
- Dragging one item to another shelf moves only it; the rest of its zone stays.
- After a relaunch it is still there, and its saved `slot` holds that shelf's name.
- The Plan list shows it under the new shelf with "Back with <zone>". Renaming the shelf keeps it there;
  deleting the shelf sends it back.
- An item added by hand shows as a gray tile with its name.
- A cabinet with no shelves shows "Set Up Cabinet".
- With VoiceOver on, "Move <item> to <shelf>" moves it.
- A cabinet saved before this change opens and looks right: nothing new is saved, so nothing is migrated.

## Things the builder should look at first
- A phone photo is stored turned on its side with a rotation tag. The boxes are fractions of the upright
  photo. `UIImage` draws it upright, so the two should agree; confirm with the first screenshot before
  building the drag.
- A shelf typed in by hand has no rectangle of its own and gets a band from `CabinetLayout.rects`. With no
  detected shelves at all, the bands split the whole photo evenly, which may not match the real shelves.
  That is accepted here.
