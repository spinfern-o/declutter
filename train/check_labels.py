"""Check a Roboflow YOLO-seg export against LABELING.md before training on it.

Errors (exit code 1) are broken data the model would learn wrong things from.
Warnings are rule breaks worth a look: labels under the size rule, photos with no
labels, classes missing from valid, and photos that look alike across splits.

usage: python train/check_labels.py EXPORT   (the .zip, or the unzipped folder)
"""
import csv
import sys
import tempfile
import zipfile
from collections import Counter
from pathlib import Path

import yaml
from PIL import Image

CLASSES = {r["class"] for r in csv.DictReader(open(Path(__file__).parent / "classes.csv"))}
SPLITS = ("train", "valid", "test")
MIN_PX = 30  # LABELING.md size rule, measured on the photo shrunk to 640 px
NEAR = 4  # dhash bits (of 64) two photos may differ by and still look like the same shot

if len(sys.argv) != 2:
    sys.exit(__doc__)
src = Path(sys.argv[1]).expanduser()
if src.suffix == ".zip":
    tmp = tempfile.TemporaryDirectory()
    zipfile.ZipFile(src).extractall(tmp.name)
    root = Path(tmp.name)
else:
    root = src
if not (root / "data.yaml").exists():
    sys.exit(f"No data.yaml in {src}. Pass a Roboflow YOLO export (zip or folder).")

errors, warnings = [], []
names = yaml.safe_load((root / "data.yaml").read_text())["names"]
names = list(names.values()) if isinstance(names, dict) else names
if set(names) - CLASSES:
    errors.append(f"data.yaml: classes not in classes.csv (typo?): {sorted(set(names) - CLASSES)}")
if CLASSES - set(names):
    warnings.append(f"data.yaml: no labels anywhere for {sorted(CLASSES - set(names))}")


def dhash(im):
    # 64-bit "difference hash": survives resizing and re-encoding, so Roboflow's copies still match
    px = im.convert("L").resize((9, 8)).tobytes()
    return sum(1 << i for i in range(64) if px[i // 8 * 9 + i % 8] > px[i // 8 * 9 + i % 8 + 1])


counts = {s: Counter() for s in SPLITS}
small = {s: [] for s in SPLITS}  # (px at 640, label) per split, summarized at the end
photos = []  # (split, source photo, path in export, dhash)
for split in SPLITS:
    img_dir, lab_dir = root / split / "images", root / split / "labels"
    if not img_dir.is_dir():
        errors.append(f"{split}/: missing (export with a train, valid and test split)")
        continue
    images = {p.stem: p for p in img_dir.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png"}}
    for lab in lab_dir.glob("*.txt"):
        if lab.stem not in images:
            errors.append(f"{split}/labels/{lab.name}: label file with no photo")

    for stem, img in sorted(images.items()):
        where = f"{split}/{img.name}"
        with Image.open(img) as im:
            w, h = im.size
            # Roboflow names files "<original>_jpg.rf.<hash>.jpg"; the part before .rf. is the source photo
            photos.append((split, stem.split(".rf.")[0], where, dhash(im)))
        lab = lab_dir / f"{stem}.txt"
        lines = [l for l in lab.read_text().splitlines() if l.strip()] if lab.exists() else []
        if not lines:
            warnings.append(f"{where}: no labels (rule 2: label every item)")
        scale = 640 / max(w, h)
        for n, line in enumerate(lines, 1):
            try:
                cls, *xy = line.split()
                cls, xy = int(cls), [float(v) for v in xy]
            except ValueError:
                errors.append(f"{where} line {n}: not a class number followed by coordinates")
                continue
            if not 0 <= cls < len(names):
                errors.append(f"{where} line {n}: class {cls} doesn't exist (data.yaml has {len(names)})")
                continue
            if len(xy) < 6 or len(xy) % 2:
                errors.append(f"{where} line {n}: {names[cls]} is not a polygon (needs 3+ x,y points; boxes don't count)")
                continue
            if min(xy) < 0 or max(xy) > 1:
                errors.append(f"{where} line {n}: {names[cls]} has coordinates outside 0-1")
            xs, ys = xy[0::2], xy[1::2]
            size = max((max(xs) - min(xs)) * w, (max(ys) - min(ys)) * h) * scale
            if size < MIN_PX:
                small[split].append((size, f"{where} line {n} ({names[cls]})"))
            counts[split][names[cls]] += 1

# leaks: the same photo, or a near-identical shot, in two splits inflates the valid/test score
for i, (s1, src1, p1, h1) in enumerate(photos):
    for s2, src2, p2, h2 in photos[i + 1:]:
        if s1 == s2:
            continue
        if src1 == src2:
            errors.append(f"same photo in two splits: {p1} and {p2}")
        elif bin(h1 ^ h2).count("1") <= NEAR:
            warnings.append(f"look alike across splits (same room?): {p1} and {p2}")

for split, items in small.items():
    if items:
        by_class = Counter(label.rsplit("(", 1)[1].rstrip(")") for _, label in items)
        size, label = min(items)
        warnings.append(f"{split}: {len(items)} labels under the {MIN_PX} px size rule "
                        f"({', '.join(f'{c} {k}' for c, k in by_class.most_common())}); smallest {size:.0f} px: {label}")

for name in sorted(set(names)):
    if counts["train"][name] and not counts["valid"][name]:
        warnings.append(f"valid has no {name}, so its score for {name} can't be measured")
    for split in ("valid", "test"):
        if counts[split][name] and not counts["train"][name]:
            warnings.append(f"{split} has {name} but train has none: the model can't learn it, so {split} scores drop")

print(f"{'class':<14}" + "".join(f"{s:>7}" for s in SPLITS))
for name in sorted(CLASSES):
    print(f"{name:<14}" + "".join(f"{counts[s][name]:>7}" for s in SPLITS))
print(f"{'photos':<14}" + "".join(f"{sum(p[0] == s for p in photos):>7}" for s in SPLITS))

for kind, items in (("WARNING", warnings), ("ERROR", errors)):
    for msg in items:
        print(f"{kind}: {msg}")
print(f"\n{len(errors)} errors, {len(warnings)} warnings")
sys.exit(1 if errors else 0)
