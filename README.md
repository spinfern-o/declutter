# declutter

Photograph a cabinet, and the app finds the items in it, groups them by zone (Tech, Paper,
Toiletries…), and plans which shelf or drawer each group goes in.

## Layout

```
backend/                 Python: the model, the server, and how the model is trained
  server/app.py          web API: POST /detect takes a photo, returns items, zones and shelves as JSON
  detect.py              shared code: fix photo rotation, cut out each item, read zones
  predict.py             command-line test: run the model on one photo, save cutouts to out/
  train/                 training: labeling guide, classes.csv (the 20 classes and their zones), scripts, Colab notebook
  models/best.pt         the trained model (not in git; lives on the "model" GitHub release)
  Dockerfile, fly.toml   how the server is packaged and hosted on Fly.io

frontend/                the iPhone app (SwiftUI)
  Declutter/App/         app entry point
  Declutter/Models/      saved data: Space (a cabinet) and Item
  Declutter/Services/    talks to the server
  Declutter/Logic/       pure rules with self-checks: shelf placement, cabinet layout, 3D model lookup
  Declutter/Features/    one folder per screen
  Declutter/Resources/   Models/: your 3D models (.usdz)
```

## Run it

Server and tests, from `backend/` (the virtualenv lives at the repo root):

```bash
cd backend && ../.venv/bin/uvicorn server.app:app --port 8000
```

```bash
cd backend && ../.venv/bin/pytest -q
```

App: open `frontend/Declutter.xcodeproj` in Xcode and run it on a simulator. Debug builds talk to
`http://localhost:8000`.

Training: see `backend/train/LABELING.md`.

## Your 3D models

The "View in 3D" screen builds the cabinet from the detected shelves and puts a model of each item
on its planned shelf. Items without a model show as a gray box with their name.

- Name the file after the class in `backend/train/classes.csv`: `toothbrush.usdz`, `cardboard_box.usdz`.
- Other objects work by name: `water_bottle.usdz` is used for any item whose name contains "water bottle"
  (items you add or rename). The longest matching name wins, and plurals match.
- Any scale, Y up. The app sizes each model from how big the item was in the photo.
- Keep each file small (about 2 MB or less, textures 1024 px).
- Drop them into `frontend/Declutter/Resources/Models/` and rebuild. Nothing else to register.
