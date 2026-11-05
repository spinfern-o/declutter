from pathlib import Path

from fastapi.testclient import TestClient

from detect import split
from server.app import app

client = TestClient(app)
PHOTO = next((Path(__file__).parent.parent / "samples").rglob("*.jpg"))


def test_detect_returns_zoned_items():
    r = client.post("/detect", files={"photo": PHOTO.open("rb")})
    assert r.status_code == 200
    body = r.json()
    assert body["items"], "expected the model to find something in a sample photo"
    for item in body["items"]:
        assert item["zone"] in body["zones"]
        assert item["cutout"]
        x, y, w, h = item["box"]
        assert 0 <= x and 0 <= y and w > 0 and h > 0 and x + w <= 1 and y + h <= 1
    for shelf in body["shelves"]:  # empty until the model is trained with the shelf class
        x, y, w, h = shelf["box"]
        assert 0 <= x and 0 <= y and w > 0 and h > 0 and x + w <= 1 and y + h <= 1
    assert "Structure" not in body["zones"]


def test_split_keeps_shelves_out_of_items_and_sorts_them():
    zone_of = {"pen": "Office", "shelf": "Structure"}
    found = [("shelf", 0.9, None, (0, 50, 10, 60)), ("pen", 0.8, None, (1, 1, 2, 2)),
             ("shelf", 0.7, None, (0, 5, 10, 20)), ("mystery", 0.5, None, (3, 3, 4, 4))]
    items, shelves = split(found, zone_of)
    assert [d[0] for d in items] == ["pen", "mystery"]  # an unknown class stays an item
    assert [d[3][1] for d in shelves] == [5, 50]


def test_rejects_non_image():
    r = client.post("/detect", files={"photo": ("note.txt", b"not a photo", "text/plain")})
    assert r.status_code == 400


def test_split_keeps_one_shelf_per_level():
    # YOLO keeps overlapping boxes of one class; a near-duplicate or a box spanning two levels must not become a slot
    found = [("shelf", 0.6, None, (0, 0, 100, 100)),  # spans both levels
             ("shelf", 0.9, None, (0, 0, 100, 50)),
             ("shelf", 0.8, None, (0, 50, 100, 100)),
             ("shelf", 0.7, None, (2, 1, 100, 49))]  # near-duplicate of the top level
    _, shelves = split(found, {"shelf": "Structure"})
    assert [d[3] for d in shelves] == [(0, 0, 100, 50), (0, 50, 100, 100)]
