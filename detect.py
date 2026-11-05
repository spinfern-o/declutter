"""Shared by predict.py and the app server: photo -> upright image -> per-item cutouts -> zones."""
import csv
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

CLASSES = Path(__file__).parent / "train" / "classes.csv"


def load_zones():
    """{class: zone} from classes.csv, plus the zones in file order."""
    with open(CLASSES, newline="") as f:
        zone_of = {row["class"]: row["zone"] for row in csv.DictReader(f)}
    return zone_of, list(dict.fromkeys(zone_of.values()))


def upright(photo):
    # phone photos are stored sideways with an EXIF rotate tag; apply it so the
    # model and the cutouts see the exact same upright pixels
    return ImageOps.exif_transpose(Image.open(photo)).convert("RGB")


def cutouts(result, img):
    """Yield (class name, confidence, RGBA cutout) for each item the model found."""
    if result.masks is None:
        return
    img = img.convert("RGBA")
    for box, polygon in zip(result.boxes, result.masks.xy):
        if len(polygon) < 3:  # a tiny item's mask can come back with no outline
            continue

        # mask polygon is already in original-photo pixels; paint it white on black
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).polygon([tuple(p) for p in polygon], fill=255)

        cutout = img.copy()
        cutout.putalpha(mask)  # mask becomes transparency: only the item stays visible
        yield result.names[int(box.cls)], float(box.conf), cutout.crop(mask.getbbox())
