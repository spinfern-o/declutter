"""Pick TACO photos with wrappers and plastic bags, download them, and write YOLO-seg labels
using our 19 classes (see LABELING.md). The output folder can be uploaded to Roboflow as is.

TACO (CC BY 4.0): https://github.com/pedropro/TACO. Get its data/annotations.json first.

usage: python train/taco.py ANNOTATIONS_JSON OUT_DIR [COUNT]
"""
import csv
import io
import json
import sys
from collections import defaultdict
from pathlib import Path

import requests
from PIL import Image, ImageOps

CLASSES = [r["class"] for r in csv.DictReader(open(Path(__file__).parent / "classes.csv"))]

# TACO category name -> our class; None = skip (too small for the 30 px rule)
TACO_MAP = {
    "Aluminium foil": "wrapper", "Other plastic wrapper": "wrapper", "Crisp packet": "wrapper",
    "Plastic film": "plastic_bag", "Garbage bag": "plastic_bag", "Single-use carrier bag": "plastic_bag",
    "Polypropylene bag": "plastic_bag",
    "Other plastic bottle": "bottle", "Clear plastic bottle": "bottle", "Glass bottle": "bottle",
    "Food Can": "bottle", "Aerosol": "bottle", "Drink can": "bottle", "Glass jar": "bottle",
    "Squeezable tube": "bottle", "Spread tub": "bottle",
    "Other carton": "cardboard_box", "Egg carton": "cardboard_box", "Drink carton": "cardboard_box",
    "Corrugated carton": "cardboard_box", "Meal carton": "cardboard_box", "Pizza box": "cardboard_box",
    "Magazine paper": "paper", "Tissues": "paper", "Wrapping paper": "paper", "Normal paper": "paper",
    "Paper bag": "paper", "Plastified paper bag": "paper",
    "Battery": "battery",
    "Cigarette": None, "Plastic bottle cap": None, "Metal bottle cap": None, "Pop tab": None,
}  # everything else (cups, lids, straws, styrofoam, containers, ...) -> "other"
TARGET = {"wrapper", "plastic_bag"}
INDOOR = 1  # TACO scene category "Indoor, Man-made"

ann_path, out = Path(sys.argv[1]), Path(sys.argv[2])
count = int(sys.argv[3]) if len(sys.argv) > 3 else 80

d = json.loads(ann_path.read_text())
cat_name = {c["id"]: c["name"] for c in d["categories"]}
by_image = defaultdict(list)
for a in d["annotations"]:
    by_image[a["image_id"]].append(a)
indoor = {s["image_id"] for s in d["scene_annotations"] if INDOOR in s["background_ids"]}


def our_class(a):
    return TACO_MAP.get(cat_name[a["category_id"]], "other")


def score(img):
    # count bags/wrappers at least 5% of the photo wide, so they survive the shrink to 640 px
    big = sum(1 for a in by_image[img["id"]]
              if our_class(a) in TARGET and a["bbox"][2] >= 0.05 * img["width"])
    return (big > 0, img["id"] in indoor, big)


picked = sorted((i for i in d["images"] if score(i)[0]), key=score, reverse=True)
(out / "images").mkdir(parents=True, exist_ok=True)
(out / "labels").mkdir(exist_ok=True)

saved = 0
for img in picked:
    if saved == count:
        break
    name = f"taco_{img['id']:04d}"
    try:
        # requests ships its own CA bundle; python.org's Python on macOS often has none
        r = requests.get(img["flickr_640_url"], timeout=30)
        r.raise_for_status()
        photo = ImageOps.exif_transpose(Image.open(io.BytesIO(r.content))).convert("RGB")
    except Exception as e:
        print(f"skip {name}: download failed ({e})")
        continue
    w, h = photo.size
    # polygons are in the annotated frame; skip photos whose orientation doesn't match it
    if abs(w / h - img["width"] / img["height"]) > 0.02:
        print(f"skip {name}: orientation mismatch")
        continue

    lines = []
    for a in by_image[img["id"]]:
        cls = our_class(a)
        if cls is None or not isinstance(a["segmentation"], list) or not a["segmentation"]:
            continue
        if max(a["bbox"][2:]) * 640 / max(img["width"], img["height"]) < 30:  # size rule, LABELING.md
            continue
        poly = max(a["segmentation"], key=len)  # multi-part objects: keep the largest part
        coords = " ".join(f"{v / (img['width'] if k % 2 == 0 else img['height']):.5f}"
                          for k, v in enumerate(poly))
        lines.append(f"{CLASSES.index(cls)} {coords}")

    photo.save(out / "images" / f"{name}.jpg", quality=92)
    (out / "labels" / f"{name}.txt").write_text("\n".join(lines) + "\n")
    saved += 1
    print(f"{name}: {len(lines)} objects{' (indoor)' if img['id'] in indoor else ''}")

(out / "data.yaml").write_text(f"names: {CLASSES}\nnc: {len(CLASSES)}\n")
(out / "CREDITS.txt").write_text(
    "Images and annotations from TACO (http://tacodataset.org), CC BY 4.0.\n"
    "Proença, P. F., & Simões, P. (2020). TACO: Trash Annotations in Context for Litter Detection.\n")
print(f"saved {saved} photos to {out}")
