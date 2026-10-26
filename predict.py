import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps
from ultralytics import YOLO

photo = sys.argv[1] if len(sys.argv) > 1 else "samples/cart.jpg"
out = Path("out")
out.mkdir(exist_ok=True)

# phone photos are stored sideways with an EXIF rotate tag; apply it so the
# model and the cutouts see the exact same upright pixels
img = ImageOps.exif_transpose(Image.open(photo)).convert("RGB")

model = YOLO("yolo11n-seg.pt")  # downloads pretrained COCO weights on first run
result = model(img, device="mps")[0]  # one photo in -> one result out

result.save(out / "annotated.jpg")  # boxes + colored masks drawn on the photo

img = img.convert("RGBA")
if result.masks is None:
    sys.exit("No objects found.")

for i, (box, polygon) in enumerate(zip(result.boxes, result.masks.xy)):
    name = result.names[int(box.cls)]
    conf = float(box.conf)
    print(f"{i}: {name:<12} confidence {conf:.2f}")

    # mask polygon is already in original-photo pixels; paint it white on black
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon([tuple(p) for p in polygon], fill=255)

    cutout = img.copy()
    cutout.putalpha(mask)  # mask becomes transparency: only the item stays visible
    cutout.crop(mask.getbbox()).save(out / f"{i}_{name}.png")