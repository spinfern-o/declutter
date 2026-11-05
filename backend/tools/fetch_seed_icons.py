"""Download the 3D-style pictures listed in icon_map.csv from Microsoft Fluent Emoji
(MIT, https://github.com/microsoft/fluentui-emoji) into icons_src/, named after our objects,
ready for import_icons.py. Also saves the license next to the app's icons.

usage: python tools/fetch_seed_icons.py   (from backend/), then python tools/import_icons.py tools/icons_src
"""
import csv
import sys
from pathlib import Path
from urllib.parse import quote

import requests

HERE = Path(__file__).parent
REPO = "microsoft/fluentui-emoji"
RAW = f"https://raw.githubusercontent.com/{REPO}/main"
ICONS = HERE.parent.parent / "frontend" / "Declutter" / "Resources" / "Icons"

out = HERE / "icons_src"
out.mkdir(exist_ok=True)

# one listing call; objects keep their 3D picture at assets/<Name>/3D/<name>_3d.png
tree = requests.get(f"https://api.github.com/repos/{REPO}/git/trees/main?recursive=1", timeout=60)
tree.raise_for_status()
pngs = {p.split("/")[1].lower(): p for p in (t["path"] for t in tree.json()["tree"])
        if p.count("/") == 3 and "/3D/" in p and p.endswith(".png")}

missing, stand_ins = [], []
for row in csv.DictReader(open(HERE / "icon_map.csv")):
    path = pngs.get(row["fluent"].lower())
    if path is None:
        missing.append(row["fluent"])
        continue
    r = requests.get(f"{RAW}/{quote(path)}", timeout=60)
    r.raise_for_status()
    (out / f"{row['object']}.png").write_bytes(r.content)
    if row["note"].startswith("stand-in"):
        stand_ins.append(f"{row['object']} ({row['note']})")

license = requests.get(f"{RAW}/LICENSE", timeout=60)
license.raise_for_status()
ICONS.mkdir(parents=True, exist_ok=True)
(ICONS / "ICONS_LICENSE.md").write_text(
    f"Cartoon pictures from Microsoft Fluent Emoji: https://github.com/{REPO}\n\n```\n{license.text.strip()}\n```\n")

print(f"Downloaded {len(list(out.glob('*.png')))} pictures to {out}")
if stand_ins:
    print("Stand-ins worth replacing with your own picture:", "; ".join(stand_ins))
if missing:
    sys.exit(f"Not found in Fluent Emoji: {', '.join(missing)}")
