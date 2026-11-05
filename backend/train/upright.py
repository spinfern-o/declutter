"""Make photos safe to upload for labeling.

Phones save photos sideways plus an EXIF "rotate me" tag, and not every tool honors
the tag (Roboflow's SAM 3 auto-label didn't), so masks land on the wrong pixels.
This rotates the pixels for real, drops all EXIF (also strips GPS location),
and caps the long side at 4096 px like the app does.

usage: python train/upright.py IN_DIR OUT_DIR
"""
import sys
from pathlib import Path

from PIL import Image, ImageOps

MAX_SIDE = 4096

if len(sys.argv) != 3:
    sys.exit(__doc__)
src, dst = Path(sys.argv[1]).expanduser(), Path(sys.argv[2])
if not src.is_dir():
    sys.exit(f"Folder not found: {src}\nExport your photos into a folder first, then pass that folder.")
dst.mkdir(parents=True, exist_ok=True)

for f in sorted(src.iterdir()):
    if f.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
        if not f.name.startswith("."):
            print(f"skipped {f.name} (only .jpg/.jpeg/.png; export HEIC as JPEG first)")
        continue
    img = ImageOps.exif_transpose(Image.open(f)).convert("RGB")
    img.thumbnail((MAX_SIDE, MAX_SIDE))  # only ever shrinks
    img.save(dst / f"{f.stem}.jpg", quality=92)  # no exif= argument, so no tags are written
    print(f"{f.name} -> {img.size}")
