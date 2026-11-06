# 3D models from the server, a 3D cabinet on tap, and draggable cabinets

Status: approved in chat on 2026-11-05 ("go with option 2"). This file is both the spec and the plan.

## Intent
- Tapping a cabinet in the 3D room shows that cabinet in 3D with its organized items (the room plan), not only a list.
- Items show as the user's own USDZ models, and those models live on the backend, so a changed model reaches every phone
  without an app update.
- Cabinets in the 3D room can be dragged to a new spot on the floor (the later marketplace builds on this).

## Decided
- **Option 2:** model files ship inside the server image, like `best.pt`. The deploy workflow downloads every `.usdz` from
  the GitHub release `models-3d` into `backend/models3d/`. A server restart or redeploy brings them back. Updating a model
  means uploading it to that release and redeploying.
- The app asks the server for a list of models with a fingerprint each. It downloads only new or changed files, keeps them
  on the phone, and uses the saved copies offline. A model missing everywhere shows as today's gray box.

## Non-goals
- A separate storage bucket (option 3), the marketplace, editing items inside the 3D cabinet, rotating cabinets by drag.

## Global constraints
- No unrequested UI polish; logic goes in `Logic/` with assert self-checks; the test commands are
  `cd backend && ../.venv/bin/pytest -q` and `frontend/scripts/selfcheck.sh 2DED3EFA-5004-4C30-8CAA-A9A0804FAF8C`.
- Names that come from the server become file names on the phone: only `[a-z0-9_]+` is accepted (trust boundary).

### Task 1: The backend serves 3D models
- `backend/server/app.py`: `GET /models` returns `{"models": {"<name>": "<sha256 first 16 hex>"}}` for every
  `backend/models3d/*.usdz`, with hashes cached by (size, mtime). The files themselves are served by a `StaticFiles`
  mount at `/models/files`, which rejects path tricks.
- `backend/models3d/.gitkeep` tracked; the `.usdz` files are git-ignored (they live on the release).
- `backend/Dockerfile`: `COPY models3d/ models3d/`.
- `.github/workflows/fly-deploy.yml`: `mkdir -p backend/models3d` then
  `gh release download models-3d --pattern '*.usdz' --dir backend/models3d || echo "no models-3d release yet"`.
  How to update one: `gh release upload models-3d backend/models3d/<name>.usdz --clobber`, then redeploy.
- Test first (`backend/server/test_app.py`): a temporary `zz_test.usdz` appears in `/models` with a 16-hex hash, the hash
  changes when the file changes, `/models/files/zz_test.usdz` returns its bytes, `/models/files/../app.py` is not served.
- Expected: the new test fails before the endpoint exists, then `pytest -q` passes.

### Task 2: The app downloads changed models
- `Services/ModelStore.swift` (@Observable, shared): `sync()` fetches `/models`, downloads changed files into
  `Application Support/Models/`, deletes saved models the server no longer lists, stores the fingerprints, and bumps
  `version`. Fetch failure keeps everything saved (offline). Runs once at launch from `DeclutterApp`.
- Pure `ModelStore.plan(server:saved:) -> (download: [String], delete: [String])` drops names that aren't `[a-z0-9_]+`;
  `selfCheck()` asserts new, changed, unchanged, removed, and a bad name.
- `ModelCatalog`: `objects` = saved downloads plus any bundled ones, refreshed after a sync; `url(for:)` prefers the download.
  `RoomView` and `CabinetSceneView` load with `Entity(contentsOf: ModelCatalog.url(for:))` and reload when `version` changes.
- Expected: the self-check fails first on the new asserts, then `selfcheck.sh` passes; in the Simulator with a test model in
  `backend/models3d/` the gray box becomes the model without rebuilding the app.

### Task 3: Tapping a cabinet shows it in 3D
- `SpotSheet` gets a 3D cabinet at the top, built by `RoomView`'s existing cabinet builder (same room plan, same shelves and
  item models), scaled to fill a fixed-height view with orbit and zoom. Read-only. The item list stays below.
- Expected: in the Simulator, tapping a cabinet in the sample room shows its shelves and items in 3D above the list.

### Task 4: Drag cabinets around the room
- `RoomView`: a drag that starts on a cabinet moves it across the floor (a drag elsewhere still orbits, as in
  `CabinetSceneView`); on release its `spot` x and z are saved, yaw and size unchanged; a tap still opens it.
- Pure `RoomGeometry.clamp(_ spot:, in corners:)` keeps the cabinet's footprint inside the room's outline box;
  `selfCheck` asserts a spot dragged past a wall comes back inside and a spot already inside is unchanged.
  `// shortcut: clamps to the outline's bounding box, so L-shaped rooms allow the missing corner`.
- Expected: the clamp asserts fail first, then `selfcheck.sh` passes; in the Simulator a cabinet dragged across the sample
  room stays where it's dropped after leaving and reopening the room.

## Review focus
- Path traversal and bad names from the server; partial or failed downloads leaving a corrupt file; the app crashing on a
  model file it can't load; drag versus orbit versus tap; whether moving a cabinet changes any plan (it must not).
