"""Stateless API for the iOS app: one photo in, items with cutouts and zones out.

Run from the repo root: uvicorn server.app:app --port 8000
"""
import base64
import io
import sys
from pathlib import Path

from fastapi import FastAPI, HTTPException, UploadFile
from PIL import UnidentifiedImageError
from ultralytics import YOLO

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from detect import cutouts, load_zones, upright  # noqa: E402

MAX_BYTES = 15 * 1024 * 1024
THUMB = 256  # long side of each cutout sent back; keeps the response small

model = YOLO(ROOT / "models" / "best.pt")  # promote.py swaps this file; redeploy to ship a new model
zone_of, zones = load_zones()
app = FastAPI()


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
    items = []
    for name, conf, cutout in cutouts(result, img):
        cutout.thumbnail((THUMB, THUMB))
        png = io.BytesIO()
        cutout.save(png, "PNG")
        items.append({
            "class": name,
            "zone": zone_of.get(name, "Misc"),  # a model/CSV mismatch must not break the app
            "confidence": round(conf, 3),
            "cutout": base64.b64encode(png.getvalue()).decode(),
        })
    return {"zones": zones, "items": items}
