"""Shared by predict.py and the app server: photo -> upright image -> per-item cutouts -> zones."""
import csv
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

CLASSES = Path(__file__).parent / "train" / "classes.csv"
STRUCTURE = "Structure"  # the zone of classes that are part of the furniture (shelf), not items to sort


def load_zones():
    """{class: zone} from classes.csv, plus the item zones in file order."""
    with open(CLASSES, newline="") as f:
        zone_of = {row["class"]: row["zone"] for row in csv.DictReader(f)}
    return zone_of, [z for z in dict.fromkeys(zone_of.values()) if z != STRUCTURE]


def split(found, zone_of):
    """Separate cutouts() output into items and shelves; shelves come back top to bottom.

    YOLO keeps overlapping boxes of one class, so the same shelf found twice, or one box spanning two
    levels, would become extra slots: of shelves that mostly overlap, only the most confident is kept.
    """
    items, shelves = [], []
    for detection in found:
        (shelves if zone_of.get(detection[0]) == STRUCTURE else items).append(detection)
    kept = []
    for shelf in sorted(shelves, key=lambda d: -d[1]):
        if all(_overlap(shelf[3], other[3]) <= 0.5 for other in kept):
            kept.append(shelf)
    # shortcut: sorted by top edge only, so sections side by side are named as levels; upgrade when carts with columns are labeled
    return items, sorted(kept, key=lambda d: d[3][1])


def _overlap(a, b):
    """How much of the smaller (left, top, right, bottom) box the two boxes share, 0 to 1."""
    width, height = min(a[2], b[2]) - max(a[0], b[0]), min(a[3], b[3]) - max(a[1], b[1])
    if width <= 0 or height <= 0:
        return 0
    smaller = min((a[2] - a[0]) * (a[3] - a[1]), (b[2] - b[0]) * (b[3] - b[1]))
    return width * height / smaller


def upright(photo):
    # phone photos are stored sideways with an EXIF rotate tag; apply it so the
    # model and the cutouts see the exact same upright pixels
    return ImageOps.exif_transpose(Image.open(photo)).convert("RGB")


def cutouts(result, img):
    """Yield (class name, confidence, RGBA cutout, bbox) for each item the model found.

    bbox is (left, top, right, bottom) in photo pixels: where the cutout sat.
    """
    if result.masks is None:
        return
    img = img.convert("RGBA")
    for box, polygon in zip(result.boxes, result.masks.xy):
        if len(polygon) < 3:  # a tiny item's mask can come back with no outline
            continue

        # mask polygon is already in original-photo pixels; paint it white on black
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).polygon([tuple(p) for p in polygon], fill=255)

        bbox = mask.getbbox()
        if bbox is None:  # an outline that covers no pixels; crop(None) would return the whole photo
            continue

        cutout = img.copy()
        cutout.putalpha(mask)  # mask becomes transparency: only the item stays visible
        yield result.names[int(box.cls)], float(box.conf), cutout.crop(bbox), bbox
