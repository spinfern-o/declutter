# Room MVP: outline your room, see it in 3D, organize every messy spot in it

Status: approved in chat on 2026-11-05 ("leave agent C out of the MVP ... deploy a and b in a worktree").
This file is both the spec and the plan. Agents A and B build from it in parallel worktrees; the
foundation section is already on branch `room-mvp`.

## Intent
A student outlines their dorm room with a regular iPhone (no LiDAR), marks where each messy storage
spot is (a cabinet, cart, shelf unit or drawer), and sees a 3D version of the room with those spots in
it. Tapping a spot shows the items detected there, already sorted by the organizer onto that spot's
detected shelves, next to every item found in the whole room, so things can be moved between spots.

## Goals
- Works on an iPhone 17 (no LiDAR). The user has one for testing.
- Each messy spot is a cabinet (`Space`) photographed and detected exactly as today.
- Every detected item goes through the organizer (`Logic/Organizer.swift` rules) onto detected shelves,
  across all spots in the room, not only within one cabinet.

## Non-goals (MVP)
- RoomPlan / LiDAR scanning (later, as an automatic upgrade on Pro phones; same `Room` data).
- The marketplace (agent C): adding furniture you can buy. Designed later.
- Drawing models over the unchanged photo.
- Exact furniture shapes in the room: spots are boxes; walls are flat.

## Anti-goals
- A room view that only works on LiDAR phones.
- Losing or silently changing cabinets that exist today: a cabinet with no room keeps working as now.

## Shared data (foundation, already built; neither agent changes these fields' meaning)
Room frame: meters, y up, floor at y = 0. x and z lie on the floor. The first corner is at the origin
and the first wall runs from corner 0 to corner 1 along +x. Corners go around the room in order.

- `Models/Room.swift` `Room` (@Model): `name`, `createdAt`, `corners: [[Double]]` ([x, z] per corner),
  `wallHeight` (default 2.4), `spaces: [Space]` (inverse of `Space.room`, nullify on delete).
  DEBUG `Room.sample(in:)`: a 4 x 3.5 m room with up to two existing cabinets against its walls.
- `Models/Space.swift` adds:
  - `room: Room?`: the room this cabinet stands in (nil = a loose cabinet, as today).
  - `spot: [Double]?`: where it stands: `[x, z, yaw, width, depth, height]`, room frame, meters; `x, z`
    is the center of its footprint on the floor; `yaw` in radians around +y, 0 = its front faces +z.
  - `Space.make(name:photo:response:in:)`: the photo -> cabinet code from `SpacesView.sort()`, reused by
    anything that photographs a cabinet (agent A's spot flow).
- App root is now a `TabView`: **Rooms** (`Features/Rooms/RoomsView.swift`) and **Cabinets** (today's
  `SpacesView`). Rooms lists rooms, opens `RoomScanView` to make one, and pushes `RoomView(room:)`.
- Stubs that compile today and are replaced by their owner:
  - `Features/RoomScan/RoomScanView.swift` (A): typed width/length -> rectangular room.
  - `Features/RoomScan/SpotScanView.swift` (A): pick an existing cabinet, typed width -> placed on wall 0.
  - `Features/Room/RoomView.swift` (B): a plain list of the room's cabinets and an "Add Messy Spot"
    button that presents `SpotScanView(room:)`.
- `frontend/scripts/selfcheck.sh SIMULATOR_UDID`: builds, installs, launches, and fails if a DEBUG
  self-check assert crashed the app. This is every task's test command.

## File ownership (the merge depends on this)
| Who | Owns (creates/edits) | Must not edit |
|---|---|---|
| A | `Features/RoomScan/**`, `Logic/RoomGeometry.swift` (+ its `selfCheck` call in `DeclutterApp`) | `Models/**`, `Features/Room/**`, `Logic/Organizer.swift`, `Logic/RoomOrganizer.swift` |
| B | `Features/Room/**`, `Logic/RoomOrganizer.swift`, may add fields to `Models/Space.swift` / `Models/Item.swift`, may extend `Logic/Organizer.swift` (+ `selfCheck` call in `DeclutterApp`) | `Features/RoomScan/**`, `Logic/RoomGeometry.swift`, the meaning of `Room`/`spot` fields |
| both | one line each in `DeclutterApp.init` for their self-check; nothing else shared | `Features/Rooms/RoomsView.swift` (foundation) |

The interfaces between them are exactly: A creates `Room`s and sets `Space.room` + `Space.spot`;
B reads them. B presents `SpotScanView(room:)` and A presents nothing of B's.

## Agent A: outline the room and place messy spots (ARKit, any iPhone)
Approach: ARKit world tracking with horizontal + vertical plane detection (no LiDAR; the Measure app's
technique) in an `ARView` (RealityKit) wrapped for SwiftUI.

1. `Logic/RoomGeometry.swift` (pure, `selfCheck()` asserts, DEBUG-called from `DeclutterApp`):
   - `normalize(_ worldCorners: [SIMD3<Float>]) -> [[Double]]`: project tapped floor points to [x, z],
     move corner 0 to the origin, rotate so corner 0 -> 1 runs along +x, make the order go around
     consistently, drop near-duplicate taps (< 10 cm apart).
   - `spot(frontLeft:frontRight:inRoomOf:)`: two taps on the floor at the cabinet's front corners ->
     `[x, z, yaw, width, depth, height]` in the room frame (default depth 0.45 m, height 0.9 m, editable).
   - Store the world -> room transform alongside the room session so later spot taps convert (keep it
     in memory for the scan session; do not add model fields).
2. `RoomScanView`: camera with a floor-snapped reticle; "Add Corner" taps raycast to the floor plane;
   a live outline; "Done" (3+ corners) names and saves the `Room`. When
   `ARWorldTrackingConfiguration.isSupported` is false (Simulator), keep today's typed width/length form.
3. `SpotScanView(room:)`: in AR, tap the cabinet's two front corners, adjust height, then either
   "Take Photo" (camera -> `API.detect` -> `Space.make` -> set `room`/`spot`) or "Use Existing Cabinet"
   (pick one with no room). Without AR support, keep the stub's typed form. Note: spot placement in AR
   needs the same world -> room transform as the room scan; if the scan session is gone, the user first
   taps two known room corners to re-align (or the MVP only allows adding spots in the same session as
   the scan; choose the simpler and say which).
4. Done when: self-checks pass in the Simulator; the typed fallback still works there; the AR flow
   builds; a short "How to test on your iPhone 17" note in the final message. Real AR is verified by
   the user on device.

## Agent B: the 3D room and room-wide organizing
1. `Logic/RoomOrganizer.swift` (pure, `selfCheck()` asserts): organize every item in the room.
   - Slots are every (cabinet, shelf) pair of the room's cabinets. Reach order across cabinets:
     interleave each cabinet's slots by their own reach rank (rank 0 of every cabinet, then rank 1 ...),
     cabinets in a stable order; reuse `Organizer`'s rules (biggest zone -> easiest slot, toss excluded,
     overflow to least-full, keep existing placements).
   - Result: which (cabinet, shelf) each zone goes to. Store it so it survives relaunch (B's choice of
     fields on `Space`/`Item`, e.g. a zone -> shelf map on the destination cabinet, or a per-item
     destination relationship; avoid UUID fields added with a default, since lightweight migration
     gives every existing row the same value).
   - Per-item override: the user can move a single item to another spot; it wins over the zone plan.
2. `RoomView(room:)`: a RealityView 3D room: floor polygon from `corners`, walls `wallHeight` tall
   (front-facing walls see-through or culled so the room is visible from outside), each cabinet a box at
   its `spot`. Messy spots stand out (e.g. tinted); reuse `CabinetLayout` + `ModelCatalog` to show its
   shelves and item models inside the box where cheap. Orbit/zoom like `CabinetSceneView`.
   "Add Messy Spot" presents `SpotScanView(room:)`.
3. Tapping a spot opens a sheet: this spot's items (the ones the room plan puts here, pre-selected)
   above every item detected in the room; selecting an item from elsewhere moves it here, deselecting
   sends it back to the plan. Grouped by zone; uses the existing `ItemRow`.
4. Test data: DEBUG "Sample Room" (foundation's `Room.sample`) gives a room without scanning.
5. Done when: self-checks pass; in the Simulator the sample room shows in 3D with its spots; tapping a
   spot shows the right items; moving an item updates both spots; relaunch keeps it.

## Each task's test
`frontend/scripts/selfcheck.sh <UDID>` (A: the iPhone 17 simulator `6B9E3E51-48DD-40CE-948F-C25098D0BD6F`;
B: iPhone 17 Pro Max `C6D90ED0-45CA-4CD0-83F9-B07DBDA8350A`, so they never install over each other)
plus the manual checks above. Write the failing assert first, watch the launch fail, then make it pass.

## Merge
Both branch from `room-mvp`. When both report back, the coordinating session merges A then B into
`room-mvp`, resolves the `DeclutterApp.init` lines, runs `selfcheck.sh`, walks the sample room, and asks
the user before pushing or opening a PR.

## Left to the builders
Visual details of the AR overlay and the 3D room (keep them plain: no unrequested polish); exact
interleaving tie-breaks; how the override is shown.
