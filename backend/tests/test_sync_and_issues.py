import hashlib
import json
import urllib.request
import urllib.error
import uuid
from datetime import datetime, timezone
import pytest

from app.db import SessionLocal
from app.models import Asset, Issue, Photo, Tag, User
from app.security import make_token

BASE_URL = "http://localhost:8000/api/v1"


def api_request(method, path, body=None, raw_body=None, token=None, content_type="application/json"):
    url = f"{BASE_URL}{path}"
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if content_type:
        headers["Content-Type"] = content_type

    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    elif raw_body is not None:
        data = raw_body

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as response:
            res_body = response.read().decode("utf-8")
            return response.status, json.loads(res_body) if res_body else {}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        try:
            parsed = json.loads(err_body)
        except Exception:
            parsed = {"detail": err_body}
        return e.code, parsed


@pytest.fixture
def auth_token():
    with SessionLocal() as db:
        user = db.query(User).filter_by(phone="+919999900004").first()
        assert user is not None
        return make_token(user.id, "access")


@pytest.fixture
def test_asset():
    with SessionLocal() as db:
        asset = db.query(Asset).first()
        assert asset is not None
        tag = db.query(Tag).filter_by(asset_id=asset.id).first()
        assert tag is not None
        return str(asset.id), tag.code


def test_inspection_push_and_issue_auto_creation(auth_token, test_asset):
    asset_id, tag_code = test_asset
    insp_id = str(uuid.uuid4())
    photo_id = str(uuid.uuid4())
    dummy_bytes = b"fake-jpeg-photo-content"
    sha = hashlib.sha256(dummy_bytes).hexdigest()

    # 1. Push inspection with a failing answer (standing_water: yes) + photo metadata
    payload = {
        "device_now": datetime.now(timezone.utc).isoformat(),
        "items": [
            {
                "type": "inspection",
                "id": insp_id,
                "data": {
                    "tag_code": tag_code,
                    "asset_id": asset_id,
                    "answers": {"standing_water": "yes", "in_good_condition": "no"},
                    "scan_method": "qr",
                    "scanned_at": datetime.now(timezone.utc).isoformat(),
                    "gps_lat": 17.1805,
                    "gps_lng": 78.2205,
                    "gps_accuracy_m": 5.0,
                    "is_mocked": False,
                },
            },
            {
                "type": "photo",
                "id": photo_id,
                "data": {
                    "inspection_id": insp_id,
                    "kind": "evidence",
                    "sha256": sha,
                    "taken_at": datetime.now(timezone.utc).isoformat(),
                    "gps_lat": 17.1805,
                    "gps_lng": 78.2205,
                    "width": 1024,
                    "height": 768,
                },
            },
        ],
    }

    status, data = api_request("POST", "/sync/push", body=payload, token=auth_token)
    assert status == 200
    statuses = {r["id"]: r["status"] for r in data["results"]}
    assert statuses[insp_id] in ("ok", "duplicate")
    assert statuses[photo_id] in ("ok", "duplicate")

    # 2. Check direct photo upload
    status_upload, up_data = api_request(
        "POST", f"/photos/{photo_id}/upload", raw_body=dummy_bytes, token=auth_token, content_type="image/jpeg"
    )
    assert status_upload == 200
    assert up_data.get("ok") is True

    # 3. Check push idempotency (duplicate item)
    status_dup, dup_data = api_request("POST", "/sync/push", body=payload, token=auth_token)
    assert status_dup == 200
    dup_statuses = {r["id"]: r["status"] for r in dup_data["results"]}
    assert dup_statuses[insp_id] == "duplicate"
    assert dup_statuses[photo_id] == "duplicate"

    # 4. Pull to verify issue was created and returned
    status_pull, pull_data = api_request("GET", "/sync/pull", token=auth_token)
    assert status_pull == 200
    assert "issues" in pull_data
    assert len(pull_data["issues"]) > 0


def test_manual_issue_reporting_and_fix_workflow(auth_token, test_asset):
    asset_id, tag_code = test_asset
    issue_id = str(uuid.uuid4())
    after_photo_id = str(uuid.uuid4())
    after_bytes = b"after-repair-photo"
    after_sha = hashlib.sha256(after_bytes).hexdigest()

    # 1. Report manual issue via push
    report_payload = {
        "device_now": datetime.now(timezone.utc).isoformat(),
        "items": [
            {
                "type": "issue",
                "id": issue_id,
                "data": {
                    "asset_id": asset_id,
                    "type": "damaged_lid",
                    "severity": "high",
                    "note": "Cracked cover found during patrol",
                },
            }
        ],
    }
    status_iss, res_data = api_request("POST", "/sync/push", body=report_payload, token=auth_token)
    assert status_iss == 200
    assert res_data["results"][0]["status"] == "ok"

    # 2. Fix the issue: push after-photo metadata + issue_update
    fix_payload = {
        "device_now": datetime.now(timezone.utc).isoformat(),
        "items": [
            {
                "type": "photo",
                "id": after_photo_id,
                "data": {
                    "issue_id": issue_id,
                    "kind": "after",
                    "sha256": after_sha,
                    "taken_at": datetime.now(timezone.utc).isoformat(),
                    "width": 1024,
                    "height": 768,
                },
            },
            {
                "type": "issue_update",
                "id": str(uuid.uuid4()),
                "data": {
                    "issue_id": issue_id,
                    "status": "fixed",
                    "note": "Replaced lid with new spare",
                },
            },
        ],
    }
    status_fix, fix_data = api_request("POST", "/sync/push", body=fix_payload, token=auth_token)
    assert status_fix == 200
    fix_statuses = {r["id"]: r["status"] for r in fix_data["results"]}
    assert fix_statuses[after_photo_id] == "ok"
    assert "ok" in [r["status"] for r in fix_data["results"] if r["type"] == "issue_update"]

    # 3. Direct upload after photo
    status_up, up_res = api_request(
        "POST", f"/photos/{after_photo_id}/upload", raw_body=after_bytes, token=auth_token, content_type="image/jpeg"
    )
    assert status_up == 200
    assert up_res.get("ok") is True
