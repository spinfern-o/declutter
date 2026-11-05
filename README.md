# declutter

Photograph a cabinet, and the app finds the items in it, groups them by zone (Tech, Paper,
Toiletries…), and plans which shelf or drawer each group goes in.

## Layout

```
backend/                 Python: the model, the server, and how the model is trained
  server/app.py          web API: POST /detect takes a photo, returns items + zones as JSON
  detect.py              shared code: fix photo rotation, cut out each item, read zones
  predict.py             command-line test: run the model on one photo, save cutouts to out/
  train/                 training: labeling guide, classes.csv (the 19 classes and their zones), scripts, Colab notebook
  tools/                 cartoon picture importer for the app
  models/best.pt         the trained model (not in git; lives on the "model" GitHub release)
  Dockerfile, fly.toml   how the server is packaged and hosted on Fly.io

frontend/                the iPhone app (SwiftUI)
  Declutter/App/         app entry point
  Declutter/Models/      saved data: Space (a cabinet) and Item
  Declutter/Services/    talks to the server
  Declutter/Logic/       pure rules with self-checks: shelf placement, photo layout, cartoon lookup
  Declutter/Features/    one folder per screen
  Declutter/Resources/   cartoon pictures
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
