# declutter

Photograph a cabinet, and the app finds the items in it, groups them by zone (Tech, Paper,
Toiletries…), and plans which shelf or drawer each group goes in.

## Layout

```
backend/                 Python: the model, the server, and how the model is trained
  server/app.py          web API: POST /detect takes a photo, returns items, zones and shelves as JSON
  detect.py              shared code: fix photo rotation, cut out each item, read zones
  predict.py             command-line test: run the model on one photo, save cutouts to out/
  train/                 training: labeling guide, classes.csv (the 20 classes, their zones and YOLOE prompts), scripts, Colab notebook
  models/best.pt         the model in use: a training run or the YOLOE build (not in git; lives on the "model" GitHub release)
  data/                  the marketplace's furniture (catalog.json) and the dorm rooms (dorms.json)
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

"Organize" opens the cabinet in 3D: it builds the cabinet from the detected shelves and puts a model of each
item on its planned shelf. Items without a model show as a gray box with their name. Drag an item to another
shelf to move just that item.

- Name the file after the class in `backend/train/classes.csv`: `toothbrush.usdz`, `cardboard_box.usdz`.
- Other objects work by name: `water_bottle.usdz` is used for any item whose name contains "water bottle"
  (items you add or rename). The longest matching name wins, and plurals match.
- Any scale, Y up. The app sizes each model from how big the item was in the photo.
- Keep each file small (about 2 MB or less, textures 1024 px).
- Drop them into `frontend/Declutter/Resources/Models/` and rebuild. Nothing else to register.

## The marketplace and the dorm finder

In a room, "Add Furniture" lists real furniture from real stores. A piece is added at its real size, and its link
opens the store's page. Both lists live in `backend/data/` and reach the app on the next deploy.

`catalog.json`: add a product only from one store listing that gives its page, its price and its size.

```json
{"id": "ikea_kallax_2x2_white", "name": "KALLAX shelf unit, white", "store": "IKEA",
 "url": "https://www.ikea.com/us/en/p/kallax-shelf-unit-white-20275814/",
 "price": 44.99, "size_in": [30.125, 15.375, 30.125], "kind": "storage", "levels": 2}
```

- `size_in` is width, depth, height in inches, as the store lists them.
- `kind` is `storage` (it gets `levels` shelves and items can be organized into it) or `furniture` (it only takes
  up its space).
- Set `checked` at the top of the file to the day you read the prices.

`dorms.json` starts empty. Add a room only with its real floor size, in feet:

```json
{"dorms": [{"school": "Your University", "hall": "Your Hall", "room": "Double", "width_ft": 12, "length_ft": 16}]}
```
