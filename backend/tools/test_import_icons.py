import json

from PIL import Image

from import_icons import SIZE, run


def test_import_squares_trims_and_reports(tmp_path):
    src, out = tmp_path / "src", tmp_path / "out"
    src.mkdir()
    # a wide object with lots of empty space around it
    img = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    img.paste((255, 0, 0, 255), (20, 40, 80, 60))
    img.save(src / "toothbrush.png")
    Image.new("RGBA", (30, 60), (0, 0, 255, 255)).save(src / "Water Bottle.png")
    (src / "aliases.csv").write_text("alias,object\nbrush,toothbrush\n")
    classes = tmp_path / "classes.csv"
    classes.write_text("class,zone\ntoothbrush,Toiletries\ntape,Office\n")

    missing = run(src, out, classes)

    assert missing == ["tape"]
    catalog = json.loads((out / "catalog.json").read_text())
    assert set(catalog) == {"toothbrush", "water_bottle"}
    assert "brush" in catalog["toothbrush"] and "water bottle" in catalog["water_bottle"]

    brush = Image.open(out / "toothbrush.png")
    assert brush.size == (SIZE, SIZE) and brush.mode == "RGBA"
    left, top, right, bottom = brush.getchannel("A").getbbox()
    assert right - left > 0.8 * SIZE  # empty margins were trimmed, so the object fills the width
    assert abs((left + right) / 2 - SIZE / 2) <= 2  # and it's centered
