# The Hugging Face model with your 20 classes, and an organized cabinet you can rearrange in 3D

Status: approved in chat on 2026-11-15. Written by hand in the format of `docs/superpowers/specs/` (the Superpowers
plugin is not enabled in this cloud session).
This file is both the spec and the plan.

## Intent
- Detection uses YOLOE, the open-vocabulary model from Hugging Face, and its classes are exactly the 20
  in `backend/train/classes.csv`, `shelf` included.
- Tapping "Organize" opens the cabinet in 3D: its shelves and each item as a gray block, already
  organized. Dragging a block moves that one item to the shelf it is dropped on, and the app keeps
  each shelf lined up. Today Organize opens a list, and a drag in 3D moves the item's whole zone.

## What I found reading the repo
- `shelf` is already the 20th row of `classes.csv` (zone `Structure`) and is in `LABELING.md`.
  `check_labels.py`, `taco.py` and `detect.py` read the class list from that file. The one stale spot
  is the Colab notebook, which still says "19 classes".
- The server test says shelves are "empty until the model is trained with the shelf class", so the
  deployed model (`train-6c-stage1`, test fitness 0.362) may not know `shelf`. Task 1 checks this.
- `CabinetSceneView` already draws the shelves as 3D boards from the detected shelf boxes and already
  shows a gray box for any item with no `.usdz` model. Gray blocks and 3D shelves need no new work.
- There is no `CLAUDE.md` in the repo, on any branch, or in git history. The constraints below come
  from your two existing specs.

## Decided (your answers)
- **Fly.io stays; only the model file changes.** `YOLO("models/best.pt")` in the pinned Ultralytics
  (8.4.184) loads a YOLOE checkpoint as YOLOE on its own, so `server/app.py`, `predict.py`,
  `promote.py` and the Dockerfile need no code change. Read in the package source, not yet run.
- **20 classes, your names.** YOLOE finds things from text. Each class gets a few plain phrases
  (`electronics`: phone, earbuds, computer mouse, remote control, calculator, power bank). The model
  looks for every phrase on its own and a class scores as high as its best phrase; this is baked into
  the model, which is saved with the 20 names from `classes.csv`, in alphabetical order as Roboflow
  exports them. (First plan: average a class's phrase embeddings into one. Measured while building:
  averaging different things finds none of them, a bus dropped from 0.96 to 0.10.)
- **The existing gate decides.** `promote.py` replaces `models/best.pt` only if YOLOE beats the current
  model on your test photos. Otherwise it prints both scores and changes nothing.
- Default checkpoint `yoloe-11l-seg`; `s` and `m` are one argument away. On Fly's shared CPU the large
  one will take a few seconds per photo instead of about one (my estimate, not measured).
- **Organize opens the 3D cabinet**, blocks already on their planned shelves. The Plan list stays
  reachable from a button on that screen.
- **One item per drag, auto-arranged.** An item moved on its own remembers its shelf. Its zone can
  still be moved as a group from the Plan list. Dropping an item back on its zone's shelf makes it
  follow the zone again.

## Non-goals
- Core ML and removing Fly.io (parked at the bottom).
- Fine-tuning YOLOE on your labeled photos. This is the follow-up if `shelf` scores poorly.
- New `.usdz` models, a "before" layout, free positioning on a shelf, dragging items between cabinets
  in the room view, adding shelf boards by hand.

## Global constraints
- No unrequested UI polish. Logic goes in `Logic/` with assert self-checks.
- Test commands: `cd backend && ../.venv/bin/pytest -q` and
  `frontend/scripts/selfcheck.sh <SIMULATOR_UDID>`.
- A cabinet saved before this change keeps working unchanged: the new `Item` field is optional.

### Task 1: YOLOE with the 20 classes (backend)
- `backend/train/classes.csv`: add a `prompts` column, a few phrases per class. `shelf`: `shelf,
  drawer`. `other`: `object, item`. Existing readers use named columns, so the extra one is harmless.
- New `backend/train/yoloe.py`: load the YOLOE checkpoint, embed every phrase, fuse them into the head,
  fold the head's phrase outputs into classes (the highest score among a class's phrases), and save to
  `train/runs/<checkpoint>/weights/best.pt`, where `promote.py` expects a run. It prints the 20 names.
- `backend/train/colab.ipynb`: "19 classes" becomes "20 classes".
- `backend/train/LABELING.md`, `README.md`: how to build, promote and ship the YOLOE model.
- Test first (`backend/server/test_app.py`): the loaded model's class names equal the classes in
  `classes.csv`, and `shelf` is one of them. Expected: fails on the current model if it predates
  `shelf`, passes with the YOLOE build; the existing `/detect` tests still pass with it.
- Shipping is yours (I can't upload release files or deploy):
  `python train/promote.py train/runs/yoloe-11l-seg <export.zip>`, then
  `gh release upload model backend/models/best.pt --clobber`, then
  `gh workflow run fly-deploy.yml --ref main`.

### Task 2: An item can have its own shelf (app logic)
- `Models/Item.swift`: `var slot: String?`, the shelf the user put this one item on in its own
  cabinet. It wins over its zone's shelf. nil means it follows its zone.
- `Logic/CabinetLayout.swift`:
  - `slot(override:zoneSlot:in:)`: the override when that shelf still exists, otherwise the zone's shelf.
  - `override(droppedOn:zoneSlot:)`: nil when dropped on the zone's own shelf, otherwise the shelf.
  - `footprints` takes each item's resolved shelf instead of looking it up by zone.
- `Models/Space.swift`: `place(_ item:in:)` next to the existing `place(_ zone:in:)`, and `replan()`
  moved here from `OrganizeView` so the 3D screen can run it too.
- Test first (`CabinetLayout.selfCheck`): an item moved on its own sits on its shelf while the rest of
  its zone stays; an override naming a deleted shelf falls back to the zone's; a drop on the zone's
  shelf clears the override. Expected: the build fails on the missing functions, then passes.

### Task 3: Organize opens the 3D cabinet, and a drag moves one item
- `Features/Space/SpaceView.swift`: "Organize" pushes `CabinetSceneView` instead of `OrganizeView`.
- `Features/Cabinet3D/CabinetSceneView.swift`:
  - runs `space.replan()` when it appears and when the shelves change, as the Plan list does today;
  - when the cabinet has no shelves yet, shows the same "Set Up Cabinet" prompt and `SlotsSheet`;
  - a "Plan" toolbar button pushes the list (`OrganizeView`);
  - each block is tagged with its item, not its zone. A drop on another shelf calls
    `space.place(item, in:)`; a drop off every shelf springs back as today;
  - VoiceOver actions become "Move <item> to <shelf>", and the summary lists items by their shelf.
- `Features/Organize/OrganizeView.swift`: drop its "View in 3D" menu entry (you arrive from 3D now).
- `Features/Room/RoomView.swift`: `cabinet(...)` uses the same resolver for items shown in their own
  cabinet, so the room and the spot sheet's 3D preview agree with the cabinet screen.
- Expected: in the Simulator, Organize shows the cabinet in 3D with gray blocks on its shelves;
  dragging one pen to another shelf moves only that pen; it is still there after relaunch.

### Task 4: The Plan list agrees with the 3D cabinet
- `Features/Organize/OrganizeView.swift`: each shelf's section lists the items on that shelf, so an
  item moved on its own appears under its new shelf with a "Back with <zone>" action. "Re-sort" also
  clears the per-item moves.
- `Features/Organize/SlotsSheet.swift`: renaming a shelf carries the items moved onto it; deleting a
  shelf sends them back to their zone.
- Expected: after Task 3's drag, the Plan list shows the pen under its new shelf; renaming that shelf
  keeps it there; deleting the shelf returns it to the other pens.

## Review focus
- Whether YOLOE's `shelf` returns one box per level (what `CabinetLayout.slots(fromShelves:)` needs) or
  the whole unit. If the boxes are wrong rather than missing, I blank its prompts so the app asks for
  shelves as it does today.
- Drag versus orbit versus the spring-back; an override pointing at a shelf that no longer exists.
- Old cabinets and old items: nothing saved changes meaning.
- `other` is "anything else", which text can't describe well: expect it to be the weakest class.

## What I can and can't verify from here
- **Swift is unverified.** This container has no Xcode and your Mac isn't connected, so I can't
  compile or run the app. I'll write it carefully against the code I've read, but a compile error is
  possible until you run `frontend/scripts/selfcheck.sh <SIMULATOR_UDID>` on your Mac.
- Building the YOLOE checkpoint needs its weights and text encoder from Ultralytics' GitHub downloads.
  I'll try it here and run `pytest` against it. If this container can't reach them, building it is
  one command on your Mac, and I'll say so plainly instead of guessing.
- Your labeled export is on your Drive, so the `promote.py` score is yours to run.
- License: YOLOE and Ultralytics are AGPL-3.0, the same as the model you run today.

## Parked: Core ML (not part of this approval)
The YOLOE checkpoint from Task 1 is what a later Core ML export starts from: Ultralytics exports it to
one `.mlpackage` (macOS or Linux) with these same 20 classes. The rest of that plan was: a Swift
decoder for the raw outputs (boxes, NMS, masks, the shelf rules from `detect.split`), `ModelStore`
reading the public `models-3d` GitHub release directly instead of the server, then deleting
`backend/server/`, the Dockerfile, `fly.toml` and the deploy workflow. The same notes are in the
prompt file delivered earlier.

Work goes on `claude/relaxed-cori-99sm8y` with a draft PR.
