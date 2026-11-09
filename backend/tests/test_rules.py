from datetime import datetime, timedelta, timezone

from app.services.rules import asset_cycles, evaluate, location_flags

T0 = datetime(2026, 11, 1, tzinfo=timezone.utc)
MAT = [
    {"key": "mat_in_place", "fail_values": ["no"], "severity": "high"},
    {"key": "standing_water", "fail_values": ["yes"]},
    {"key": "mat_condition", "fail_values": ["torn", "missing"]},
    {"key": "photo"},
]


def test_all_good_passes():
    assert evaluate(MAT, {"mat_in_place": "yes", "standing_water": "no", "mat_condition": "good"}) == []


def test_wrong_answers_fail_and_keep_severity():
    f = evaluate(MAT, {"mat_in_place": "no", "standing_water": "yes", "mat_condition": "torn"})
    assert [x["key"] for x in f] == ["mat_in_place", "standing_water", "mat_condition"]
    assert f[0]["severity"] == "high" and f[1]["severity"] == "medium"


def test_gps_within_radius_plus_accuracy_passes():
    assert location_flags(40, 15, 30, False, False) == []          # 40 <= 30 + 15
    assert location_flags(50, 15, 30, False, False) == ["location_mismatch"]


def test_mock_manual_and_missing_gps_are_flagged():
    assert location_flags(None, None, 30, True, True) == ["no_gps", "mocked_gps", "manual_entry"]


def test_cycles_on_time_late_and_missed():
    # weekly asset, period of 14 days after T0
    end = T0 + timedelta(days=14)
    assert asset_cycles(T0, [T0 + timedelta(days=6), T0 + timedelta(days=12)], 7, end) == (2, 2)
    assert asset_cycles(T0, [T0 + timedelta(days=9)], 7, end) == (1, 0)   # late on day 9; next due is day 16, outside the period
    assert asset_cycles(T0, [], 7, end) == (2, 0)
    assert asset_cycles(T0, [], 30, end) == (0, 0)                         # not due yet
