# A marketplace of real furniture for the room, and a dorm finder

Status: approved in chat on 2026-11-15 (curated real catalog; storage organizes and the rest only fits; a dorm
finder fed by the owner's data). Written by hand in this folder's format. This file is both the spec and the plan.

## Intent
- In a room's 3D view the user opens a marketplace of real furniture from real stores, adds a piece, and it stands
  in the room at its real size. It can be dragged across the floor like a cabinet, turned, and removed. A link
  opens its page at the store. The model is Roomie (roomie.com): real products dropped into a 3D dorm room.
- A storage piece (shelf unit, drawers, cart) gets shelves, so the room plan and the user can put items into it.
  Other pieces (a desk) only take up their space.
- "Find My Dorm" makes a room from a school and hall whose floor size is known.

## Decided
- **Curated catalog, on the server.** `backend/data/catalog.json` lists each product with its store, its page,
  its price, and its size in inches as the store lists it. The server serves the folder at `/data`, so a changed
  catalog reaches every phone on the next deploy. No accounts, no keys.
- **Every entry is a real listing.** An entry is added only when one store listing gives the link, the size and
  the price together. `checked` is the day the prices were read; the app shows it and says the store's page has
  today's price.
- **A piece is a `Space`** with no photo and no items of its own, marked by `productURL`. Everything that
  already works for cabinets in a room works for it: the drag, the clamp to the walls, the room plan, the spot
  sheet. Furniture is hidden from the Cabinets tab and deleted with its room.
- **Dorm sizes come from the owner.** `backend/data/dorms.json` starts empty. Nobody invents a room size.

## Non-goals
- Live store search, checkout, or prices that update themselves.
- Student-to-student listings.
- Furniture shapes: a piece is a box of its real size, as cabinets are.
- Turning or removing photographed cabinets (only marketplace pieces get those actions).

## Global constraints
- No unrequested UI polish. Logic goes in `Logic/` with assert self-checks.
- Test commands: `cd backend && ../.venv/bin/pytest -q` and `frontend/scripts/selfcheck.sh <SIMULATOR_UDID>`.
- The catalog comes from the server: the app opens only `https://` links and drops sizes no room could hold.
- New `Space` fields are optional, so saved cabinets keep working.

### Task 1: The server lists furniture and dorms
- `backend/data/catalog.json`, `backend/data/dorms.json`; `server/app.py` mounts the folder at `/data`;
  `Dockerfile` copies it.
- Test first (`server/test_app.py`): every product has a unique `[a-z0-9_]+` id, a name, a store, an `https://`
  link, a price, three sizes in inches, a kind, and levels when it is storage; every dorm has a school, a hall
  and a floor size. Expected: both fail before the files exist, then `pytest -q` passes.

### Task 2: Furniture rules (app logic)
- `Logic/Furniture.swift`: `usable(url:sizeInches:)`, `meters`, `label(sizeInches:)`, `spot(size:in:)` (the middle
  of the room, clamped), `turned(_:in:)` (a quarter turn, clamped), `shelves(_:)` (equal bands), and
  `corners(widthFeet:lengthFeet:)`.
- `Models/Space.swift`: `productURL`, `productStore`, and `Space.furniture(_:in:context:)`.
- Test first (`Furniture.selfCheck`, called from `DeclutterApp`): the asserts for each rule above.

### Task 3: The marketplace in the room
- `Services/Catalog.swift`: `Product`, `Dorm`, and the two fetches.
- `Features/Market/MarketView.swift`: the list, "Add to Room", "View at <store>".
- `Features/Market/FurnitureSheet.swift`: the actions (store link, Turn a Quarter, Remove from Room) and the sheet
  for a piece that holds nothing.
- `Features/Room/RoomView.swift`: an "Add Furniture" button; furniture drawn in its own tint, a piece with no
  shelves as one solid block; a tap opens the furniture sheet or, for storage, the spot sheet with the actions.
- `Features/Room/SpotSheet.swift`, `Features/Spaces/SpacesView.swift`, `Features/Rooms/RoomsView.swift`: the
  actions section, hiding furniture from the Cabinets tab, deleting it with its room.
- Expected: in the Simulator's sample room, Add Furniture lists the catalog; adding the KALLAX puts a teal open
  box in the middle of the room; it drags, turns and stays inside the walls; tapping it lets items be moved in;
  the desk is a solid block; Remove takes a piece out and its items go back to the plan.

### Task 4: Find My Dorm
- `Features/Rooms/DormFinderView.swift`, opened from a "Find My Dorm" button in `RoomsView`.
- Expected: with the empty list it says no dorms have been added; with an entry in `dorms.json` it lists the
  school and hall, and picking one makes a room of that size.

## Review focus
- Whether each catalog link still opens the right product and the price is still about right: they were read
  from search results on 2026-11-15, not from the stores' pages, which this session could not open.
- Removing a piece while its sheet is open; a room deleted with furniture in it.
- A storage piece joining a room that already has a plan: saved placements must not move.
