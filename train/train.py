import sys
from pathlib import Path

import yaml
from ultralytics import YOLO

HERE = Path(__file__).parent
DATA = HERE / "dataset" / "data.yaml"  # written by the Roboflow export

# must match LABELING.md; catches typos like "Pen" or a missing class in Roboflow
CLASSES = {
    "cardboard_box", "plastic_bag", "wrapper", "paper", "book", "cable", "electronics",
    "battery", "pen", "scissors", "tape", "tool", "keys", "bottle", "cosmetic",
    "toothbrush", "wipes_pack", "toy", "other",
}

names = yaml.safe_load(DATA.read_text())["names"]
names = set(names.values() if isinstance(names, dict) else names)
if names - CLASSES:
    sys.exit(f"Unexpected classes in export (typo?): {sorted(names - CLASSES)}")
if CLASSES - names:  # fine early on: a class with no labels yet isn't exported
    print(f"Note: no labels yet for {sorted(CLASSES - names)}")

model = YOLO("yolo11s-seg.pt")  # start from COCO weights (transfer learning), small size
model.train(data=DATA, epochs=100, imgsz=640, device="mps", project=HERE / "runs")
# best weights land in train/runs/train*/weights/best.pt
