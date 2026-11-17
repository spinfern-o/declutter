# Declutter

An iPhone app: photograph a cabinet, the server finds the items in it, groups them by zone (Tech, Paper,
Toiletries...) and plans which shelf each group goes on. "Organize" shows the cabinet in 3D, where items can
be dragged between shelves. Rooms hold several cabinets and organize across all of them.

## Layout

- `backend/` Python. `server/app.py` is the API (`POST /detect`, `GET /models`), `detect.py` the shared photo
  code, `train/` the labeling guide, class list, training and model-building scripts.
- `backend/data/` what the server hands the app as files: the marketplace's furniture and the dorm rooms.
- `frontend/Declutter/` SwiftUI. `Models/` saved data (SwiftData), `Logic/` pure rules, `Services/` the server
  client and 3D model downloads, `Features/` one folder per screen.
- `docs/superpowers/specs/` one file per piece of work. Each is both the spec and the plan.
- `docs/handoff/` prompts that carry unfinished work to another session.

## Commands

- Backend tests: `cd backend && ../.venv/bin/pytest -q`. They need `backend/models/best.pt` and at least one
  `.jpg` under `backend/samples/`. Both are git-ignored.
- App: `frontend/scripts/selfcheck.sh <SIMULATOR_UDID>` builds, launches, and fails if a DEBUG self-check
  assert crashed the app. This needs Xcode, so a cloud session cannot run it. Say so plainly when Swift
  changes ship unverified.
- Server: `cd backend && ../.venv/bin/uvicorn server.app:app --port 8000`. Debug app builds talk to it.

## Conventions

- Rules go in `Logic/` as pure functions with a `selfCheck()` of asserts, called from `DeclutterApp.init`
  under `#if DEBUG`. Write the failing assert first, then the code.
- No unrequested UI polish. Change what was asked for and what must change with it.
- Comments say why, in plain words. `// shortcut:` marks a deliberate simplification and names its upgrade.
- `backend/train/classes.csv` is the one list of classes, their zones and their YOLOE prompts. Change
  `LABELING.md` with it. `Organizer.tossZone` in the app must match the zone name there.
- New SwiftData fields are optional or have a plain default, so saved cabinets keep working. Do not add a
  UUID field with a default: every existing row would get the same value.
- Names that come from the server become file names on the phone. Accept only `[a-z0-9_]+`.
- The furniture catalog and the dorm list hold only real data: a product from one store listing that gives its
  page, price and size; a dorm room with its real floor size. Never fill either with invented entries.
- Furniture from the marketplace is a `Space` with `productURL` set. Code that means "a cabinet the user
  photographed" must check for `productURL == nil`.
- A spec is `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` with: Intent, Decided, Non-goals, Global
  constraints, then test-first tasks with expected results. The Superpowers plugin writes this format; write
  it by hand when the plugin is not available.
- Commit messages are one short sentence saying what changed for the person using the app.

## The model and the deploy

- `backend/models/best.pt` is not in git. It lives on the GitHub release `model`. It is either a training run
  (`train/colab.ipynb`) or the YOLOE build (`train/yoloe.py`), and must know exactly the classes in
  `classes.csv`; a server test checks this.
- `train/promote.py <run> <export.zip>` replaces `best.pt` only if the run scores higher on the test photos.
- Ship a model: `gh release upload model backend/models/best.pt --clobber`, then
  `gh workflow run fly-deploy.yml --ref main`.
- The 3D item models (`.usdz`) live on the release `models-3d`; the deploy bakes them into the server.
- A push to `main` that touches `backend/**` redeploys the Fly.io app `declutter-api`.

## Open work

See `docs/handoff/2026-11-15-mac-handoff.txt`: the app changes in the two 2026-11-15 specs were written
without Xcode and still need a build and a Simulator check, the YOLOE model has not been scored on the
labeled photos, the catalog's links and prices came from search results and need a look, `dorms.json` is
empty, and the move from Fly.io to Core ML is parked with notes.
