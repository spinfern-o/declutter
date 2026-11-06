"""Stateless API for the iOS app: one photo in, items with cutouts and zones out, plus the shelves.

Run from the repo root: uvicorn server.app:app --port 8000
"""
import base64
import hashlib
import io
import sys
from pathlib import Path

from fastapi import FastAPI, HTTPException, UploadFile
from fastapi.staticfiles import StaticFiles
from PIL import UnidentifiedImageError
from ultralytics import YOLO

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from detect import cutouts, load_zones, split, upright  # noqa: E402

MAX_BYTES = 15 * 1024 * 1024
THUMB = 256  # long side of each cutout sent back; keeps the response small

model = YOLO(ROOT / "models" / "best.pt")  # promote.py swaps this file; redeploy to ship a new model
zone_of, zones = load_zones()
MODELS3D = ROOT / "models3d"  # the user's .usdz item models; the deploy downloads them from the "models-3d" release
app = FastAPI()
app.mount("/models/files", StaticFiles(directory=MODELS3D, check_dir=False), name="models")
_fingerprints: dict[tuple[str, int, int], str] = {}


@app.get("/models")
def models():
    """Every 3D model with a fingerprint of its file, so the app downloads only new or changed ones."""
    result = {}
    for path in sorted(MODELS3D.glob("*.usdz")):
        stat = path.stat()
        key = (path.name, stat.st_size, stat.st_mtime_ns)
        if key not in _fingerprints:  # hash each version of a file once, not on every request
            _fingerprints[key] = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
        result[path.stem] = _fingerprints[key]
    return {"models": result}


@app.post("/detect")
async def detect(photo: UploadFile):
    data = await photo.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise HTTPException(400, "Photo is larger than 15 MB.")
    try:
        img = upright(io.BytesIO(data))
    except (UnidentifiedImageError, OSError):
        raise HTTPException(400, "Not an image.")

    result = model(img, verbose=False)[0]
    width, height = img.size

    def fractions(left, top, right, bottom):  # where it sat, as fractions of the photo, so the app can map it
        return [round(v, 4) for v in (left / width, top / height, (right - left) / width, (bottom - top) / height)]

    found, shelves = split(cutouts(result, img), zone_of)
    items = []
    for name, conf, cutout, bbox in found:
        cutout.thumbnail((THUMB, THUMB))
        png = io.BytesIO()
        cutout.save(png, "PNG")
        items.append({
            "class": name,
            "zone": zone_of.get(name, "Misc"),  # a model/CSV mismatch must not break the app
            "confidence": round(conf, 3),
            "cutout": base64.b64encode(png.getvalue()).decode(),
            "box": fractions(*bbox),
        })
    return {
        "zones": zones,
        "items": items,
        "shelves": [{"box": fractions(*bbox), "confidence": round(conf, 3)} for _, conf, _, bbox in shelves],
    }
