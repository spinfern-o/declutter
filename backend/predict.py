import sys
from pathlib import Path

from ultralytics import YOLO

from detect import cutouts, upright

photo = sys.argv[1] if len(sys.argv) > 1 else "samples/cart.jpg"
out = Path("out")
out.mkdir(exist_ok=True)

img = upright(photo)

model = YOLO("models/best.pt")  # current best; train/promote.py replaces it (which run: models/best.txt)
result = model(img)[0]  # one photo in -> one result out

result.save(out / "annotated.jpg")  # boxes + colored masks drawn on the photo

if result.masks is None:
    sys.exit("No objects found.")

for i, (name, conf, cutout) in enumerate(cutouts(result, img)):
    print(f"{i}: {name:<12} confidence {conf:.2f}")
    cutout.save(out / f"{i}_{name}.png")
