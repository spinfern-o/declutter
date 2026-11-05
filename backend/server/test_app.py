from pathlib import Path

from fastapi.testclient import TestClient

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


def test_rejects_non_image():
    r = client.post("/detect", files={"photo": ("note.txt", b"not a photo", "text/plain")})
    assert r.status_code == 400
