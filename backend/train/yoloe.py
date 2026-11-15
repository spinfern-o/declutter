"""Build a YOLOE model that knows exactly our classes, as a run promote.py can score.

YOLOE (https://huggingface.co/jameslahm/yoloe) finds things from text instead of from our training photos.
Each class in classes.csv lists a few phrases in its `prompts` column. The model looks for every phrase on
its own, and a class scores as high as its best phrase. All of that is baked into the saved file, so it
needs no text encoder and names its detections with our class names.

usage: python train/yoloe.py [CHECKPOINT]   (default yoloe-11l-seg.pt; yoloe-11s-seg.pt and -11m- are faster)
then:  python train/promote.py train/runs/<checkpoint> EXPORT
"""
import csv
import sys
from pathlib import Path

import torch
from torch import nn
from ultralytics import YOLOE

HERE = Path(__file__).resolve().parent
checkpoint = sys.argv[1] if len(sys.argv) > 1 else "yoloe-11l-seg.pt"

with open(HERE / "classes.csv", newline="") as f:
    prompts = {row["class"]: [p.strip() for p in row["prompts"].split(",") if p.strip()] for row in csv.DictReader(f)}
missing = [name for name, phrases in prompts.items() if not phrases]
if missing:
    sys.exit(f"classes.csv: no prompts for {missing}. YOLOE can only find what a phrase describes.")
names = sorted(prompts)  # the order Roboflow exports classes in, so promote.py can score this model on an export

# Every class gets the same number of phrase slots (its first phrase fills the spare ones), so the model's
# phrase outputs can be folded back into classes below.
slots = max(len(phrases) for phrases in prompts.values())
phrases = [(prompts[name] + prompts[name][:1] * slots)[:slots] for name in names]

model = YOLOE(checkpoint)
flat = [phrase for group in phrases for phrase in group]
model.set_classes(flat, model.get_text_pe(flat))
head = model.model.model[-1]
head.fuse(model.model.pe)  # bakes the phrases in: each one becomes an output of the head's last layers

# One phrase per class does badly for classes that hold different things (a phone and a calculator are both
# `electronics`), and averaging their embeddings finds neither. So keep one output per phrase and give each
# class the highest score among its phrases: (classes x slots) channels -> max over each class's slots.
fold = [nn.Unflatten(1, (len(names), slots)), nn.MaxPool3d((slots, 1, 1)), nn.Flatten(1, 2)]
for branch in head.cv3:
    branch[-1] = nn.Sequential(branch[-1], *fold)
head.nc = len(names)
head.no = head.nc + head.reg_max * 4
model.model.names = dict(enumerate(names))
model.model.pe = model.model.pe[:, ::slots]  # one per class; a baked head only reads how many there are

out = HERE / "runs" / Path(checkpoint).stem / "weights" / "best.pt"
out.parent.mkdir(parents=True, exist_ok=True)
model.save(out)
print(f"{len(names)} classes: {', '.join(names)}")
print(f"Saved {out}\nNext: python train/promote.py {out.parent.parent.relative_to(HERE.parent)} EXPORT")
