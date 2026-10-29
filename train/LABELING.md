# Labeling guide

Everyone who labels follows this file. Consistency matters more than precision.

Scope (v1): dorm carts, desk drawers, kitchen junk drawers, bathroom drawers.
Fridges and whole rooms are out of scope until the drawer model works.

## Classes (19)

Spell them exactly like this in Roboflow: lowercase, with underscores. The scripts read the
list from `classes.csv`, so change both together.
Classes are defined by **shape and look, not by what the item is for**.

| Class | Label these | Not these |
|---|---|---|
| `cardboard_box` | product boxes, cartons, flattened boxes | a paper envelope (`paper`) |
| `plastic_bag` | shopping bags, zip bags, packaging film | small snack wrappers (`wrapper`) |
| `wrapper` | snack wrappers, candy wrappers, small crinkly packaging | |
| `paper` | loose sheets, receipts, mail, envelopes, menus, sticky-note pads | spiral or bound notebooks (`book`) |
| `book` | books, notebooks, spiral notebooks | |
| `cable` | cords, chargers (brick + cord), adapters, extension cords | |
| `electronics` | phone, earbuds and case, mouse, power bank, remote, calculator | batteries (`battery`) |
| `battery` | AA, AAA, 9V, coin cells | power banks (`electronics`) |
| `pen` | pens, pencils, markers, highlighters | toothbrushes (`toothbrush`) |
| `scissors` | scissors of any size | utility knives (`tool`) |
| `tape` | tape rolls, tape dispensers | tape measures (`tool`) |
| `tool` | screwdriver, wrench, pliers, tape measure, utility knife, hammer | |
| `keys` | single keys, key rings with keys | |
| `bottle` | bottles, spray bottles, tubes (incl. toothpaste), jars, pill bottles | |
| `cosmetic` | makeup, lipstick, compacts, nail polish, mascara | lotion tubes (`bottle`) |
| `toothbrush` | toothbrushes, floss containers | |
| `wipes_pack` | wet-wipe packs, tissue packs | tissue *boxes* (`cardboard_box`) |
| `toy` | plush toys, figurines, small toys | |
| `other` | any other item at least 30 px wide (see size rule) | |

If an item could fit two classes, choose using the "Not these" column. If it's still
unclear, use `other` and add the case to **Decisions log** below so everyone handles it the same way.

## Labeling rules

1. **One polygon per item, around the visible part only.** Don't guess at hidden edges.
2. **Label every item in every photo.** An unlabeled pen teaches the model that pens are background.
3. **Occlusion:** label an item only if roughly a third or more of it is visible. Otherwise skip it.
4. **Size rule:** skip anything smaller than about 30 px once the photo is shrunk to 640 px
   (roughly 1/20 of the photo's width). This covers paper clips, hair ties and rubber bands.
   If it's big enough, label it `other`.
5. **Groups:** label each item on its own (three pens = three polygons). Exception: a bundle
   you can't separate by eye, like a tangle of cables, gets one polygon.
6. **Items in packaging:** if you can see the item, label the item. If you only see the
   box, label `cardboard_box`.
7. **Furniture is never labeled**: desks, shelves, drawers, carts. It's background.
   Portable containers (baskets, caddies, bins, boxes) are items: label them `other`
   (or `cardboard_box` for cardboard), even when they hold other things.
8. **Label only the space the photo is about.** The floor, walls, windowsills, and anything
   in the background (another desk across the room, a backpack on the floor, a neighboring
   cart) are not labeled, even if they're items.

## Taking photos

- Mostly top-down, with the whole drawer in frame. Use the normal camera: no zoom, no filters.
- About 20% of photos from an angle, like a person casually snapping the drawer.
- Vary everything except the subject: different drawers, daylight vs. lamp light, tidy vs. very messy,
  items touching and overlapping, a few nearly empty drawers.
- Aim for at least 50 labeled instances per class. Rare classes (`battery`, `keys`,
  `toothbrush`) may need photos staged on purpose.

## Roboflow setup

- Project type: **Instance Segmentation** (not Object Detection).
- Add all 19 classes in the Classes tab before labeling.
- Use the SAM smart-polygon tool, then fix the edges by hand where needed.
- Export: format **YOLOv8 / YOLO11 segmentation**, keeping the splits you assigned.
- Before training, run `python train/check_labels.py <export.zip>`. Fix every ERROR in Roboflow
  and export again; read the warnings (size rule, classes missing from a split, look-alike photos
  across splits).
- Upload the zip to `My Drive/declutter/` and run `train/colab.ipynb` on Colab. It trains on the newest zip.
- Download the run into `train/runs/`, then run `python train/promote.py train/runs/<run> <export.zip>`.
  It replaces `models/best.pt` (what `predict.py` loads) only if the run scores higher on the test photos.

## Decisions log

Add a line here whenever you settle a confusing case, e.g.:

- Toothpaste tube → `bottle` (classes go by shape, not use).
- Sticky-note pad → `paper`.
