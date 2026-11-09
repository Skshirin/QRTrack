"""Pure business rules (no database) so they are easy to unit test."""
from datetime import datetime, timedelta


def evaluate(questions: list[dict], answers: dict) -> list[dict]:
    """Return failing questions: [{'key':..., 'severity':...}]. A question fails when the
    answer is one of its `fail_values`."""
    fails = []
    for q in questions or []:
        fv = q.get("fail_values")
        if fv and answers.get(q["key"]) in fv:
            fails.append({"key": q["key"], "severity": q.get("severity", "medium")})
    return fails


def location_flags(distance_m, accuracy_m, radius_m, is_mocked: bool, manual: bool) -> list[str]:
    flags = []
    if distance_m is None:
        flags.append("no_gps")
    elif distance_m > radius_m + (accuracy_m or 0):
        flags.append("location_mismatch")
    if is_mocked:
        flags.append("mocked_gps")
    if manual:
        flags.append("manual_entry")
    return flags


def asset_cycles(prev: datetime, times: list[datetime], interval_days: int, end: datetime):
    """Walk the inspection schedule of one asset up to `end`.
    prev  = last inspection before the period (or the asset's creation time)
    times = inspection times (sorted) that happened after `prev`
    Returns (cycles_due, cycles_on_time). A cycle is 'on time' when an inspection happens
    on or before prev + interval."""
    step = timedelta(days=interval_days)
    times = sorted(times)
    due_n = ok_n = 0
    due = prev + step
    while due <= end:
        due_n += 1
        t = next((x for x in times if x > prev), None)
        if t is not None and t <= due:
            ok_n += 1
            prev = t
        elif t is not None:      # late inspection: schedule restarts from it
            prev = t
        else:                    # missed entirely
            prev = due
        due = prev + step
    return due_n, ok_n
