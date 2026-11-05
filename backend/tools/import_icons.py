"""Turn a folder of pictures into the app's cartoon icons.

Name each file after the object it shows (toothbrush.png, water_bottle.png); PNG or WebP with a
transparent background works best. tools/aliases.csv, and an aliases.csv inside the folder, add
extra words that point at an object (alias,object). Output: square 256 px PNGs plus catalog.json in
the app's Resources/Icons. Re-run any time to add or replace pictures.

usage: python tools/import_icons.py SRC_DIR   (from backend/)
"""
import csv
import json
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).parent
CLASSES = HERE.parent / "train" / "classes.csv"
OUT = HERE.parent.parent / "frontend" / "Declutter" / "Resources" / "Icons"
SIZE = 256
MARGIN = 0.06  # empty space around the object, as a fraction of its longest side


def square(img):
    """Trim transparent edges, center on a square canvas, resize to SIZE."""
    img = img.convert("RGBA")
    box = img.getchannel("A").getbbox()
    if box:
        img = img.crop(box)
    side = round(max(img.size) * (1 + 2 * MARGIN))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def run(src, out=OUT, classes_csv=CLASSES):
    """Import every picture in src into out; return the classes that still have no picture."""
    out.mkdir(parents=True, exist_ok=True)
    catalog_path = out / "catalog.json"
    # object -> words that should show its picture; the file is <object>.png
    catalog = json.loads(catalog_path.read_text()) if catalog_path.exists() else {}

    for f in sorted(src.iterdir()):
        if f.suffix.lower() not in {".png", ".webp"}:
            continue
        obj = f.stem.strip().lower().replace(" ", "_").replace("-", "_")
        square(Image.open(f)).save(out / f"{obj}.png")
        catalog[obj] = sorted(set(catalog.get(obj, [])) | {obj.replace("_", " ")})

    for aliases in (HERE / "aliases.csv", src / "aliases.csv"):
        if aliases.exists():
            for row in csv.DictReader(open(aliases)):
                obj = row["object"].strip().lower()
                if obj in catalog:
                    catalog[obj] = sorted(set(catalog[obj]) | {row["alias"].strip().lower()})

    catalog_path.write_text(json.dumps(catalog, indent=1, sort_keys=True) + "\n")
    classes = [r["class"] for r in csv.DictReader(open(classes_csv))]
    return [c for c in classes if c not in catalog]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1]).expanduser()
    if not src.is_dir():
        sys.exit(f"Folder not found: {src}")
    missing = run(src)
    print(f"{len(json.loads((OUT / 'catalog.json').read_text()))} pictures in {OUT}")
    if missing:
        print("Classes with no picture yet (they show the generic 'other' picture):", ", ".join(missing))
