"""Replace models/best.pt with a new training run's weights if they score better.

Both models are scored on the same photos, the export's test split. Each run's own
fitness comes from its own valid set, so it can't be compared across exports.

usage: python train/promote.py RUN_DIR EXPORT   (EXPORT: the .zip or folder the run trained on)
"""
import shutil
import sys
import tempfile
import zipfile
from datetime import date
from pathlib import Path

import yaml
from ultralytics import YOLO

MODEL = Path(__file__).resolve().parent.parent / "models" / "best.pt"  # what predict.py loads
MARGIN = 0.03  # with ~10 test photos, smaller gaps are noise

if len(sys.argv) != 3:
    sys.exit(__doc__)
run, src = Path(sys.argv[1]).expanduser(), Path(sys.argv[2]).expanduser()
new = run / "weights" / "best.pt"
if not new.exists():
    sys.exit(f"No weights at {new}. Pass the run folder you downloaded, e.g. train/runs/train-7")

tmp = Path(tempfile.mkdtemp())
if src.suffix == ".zip":
    zipfile.ZipFile(src).extractall(tmp / "export")
    root = tmp / "export"
else:
    root = src.resolve()
if not (root / "test" / "images").is_dir():
    sys.exit(f"No test split in {src}. Pass the Roboflow export the run trained on.")

# Roboflow's data.yaml points one folder up; write a copy that points at the export itself
data = yaml.safe_load((root / "data.yaml").read_text())
names = list(data["names"].values()) if isinstance(data["names"], dict) else data["names"]
data.update(path=str(root), train="train/images", val="valid/images", test="test/images")
(tmp / "data.yaml").write_text(yaml.safe_dump(data))

new_names = list(YOLO(new).names.values())
if new_names != names:
    # a YOLOE build has its classes baked in and crashes the validator on any other list
    missing = [n for n in new_names if n not in names]
    sys.exit(f"{run.name} has {len(new_names)} classes but the export has {len(names)}, so it can't be scored "
             f"on this export.\nThe export is missing: {', '.join(missing) or 'none'}. The usual cause is classes "
             f"with no labels in the export; Roboflow leaves those out.\n"
             f"If {run.name} is good, replace it by hand: cp {new} {MODEL}")


def score(weights):
    m = YOLO(weights).val(data=tmp / "data.yaml", split="test", imgsz=640, plots=False,
                          verbose=False, project=tmp, name="val", exist_ok=True)
    return m.box.map + m.seg.map  # fitness, the same number Ultralytics uses to pick best.pt


def promote(note):
    MODEL.parent.mkdir(exist_ok=True)
    shutil.copy(new, MODEL)
    (MODEL.parent / "best.txt").write_text(f"{run.name} ({date.today()}): {note}\n")
    print(f"Promoted {run.name} -> {MODEL}")


if not MODEL.exists():
    promote(f"test fitness {score(new):.3f}, first model")
    sys.exit()

old_names = list(YOLO(MODEL).names.values())
if old_names != names:
    # class numbers mean different things now (Roboflow sorts names), so the old model can't be scored here
    sys.exit(f"Classes changed since the current model ({len(old_names)} -> {len(names)}), so it can't be "
             f"scored on this export.\nIf {run.name} is good, replace it by hand: cp {new} {MODEL}")

new_fit, old_fit = score(new), score(MODEL)
print(f"test fitness: {run.name} {new_fit:.3f} | current model {old_fit:.3f}")
if new_fit >= old_fit + MARGIN:
    promote(f"test fitness {new_fit:.3f}, replaced {old_fit:.3f}")
else:
    print(f"Kept the current model ({run.name} needs {old_fit + MARGIN:.3f} or more to replace it).")
