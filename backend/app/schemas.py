"""Plain dict serialisers shared by the sync and dashboard endpoints."""
from datetime import datetime, timezone


def iso(d):
    return d.isoformat() if d else None


def asset_state(a, now=None) -> str:
    now = now or datetime.now(timezone.utc)
    if a.status != "active":
        return "inactive"
    if a.next_due_at and a.next_due_at < now:
        return "overdue"
    if a.next_due_at and a.next_due_at.date() <= now.date():
        return "due_today"
    return "done"


def asset_out(a):
    return {"id": str(a.id), "type_id": str(a.type_id), "zone_id": str(a.zone_id), "name": a.name,
            "lat": a.lat, "lng": a.lng, "status": a.status, "interval_days": a.interval_days,
            "next_due_at": iso(a.next_due_at), "last_inspected_at": iso(a.last_inspected_at),
            "assigned_to": str(a.assigned_to) if a.assigned_to else None, "state": asset_state(a)}


def issue_out(i):
    return {"id": str(i.id), "asset_id": str(i.asset_id), "inspection_id": str(i.inspection_id) if i.inspection_id else None,
            "type": i.type, "severity": i.severity, "status": i.status, "note": i.note,
            "assigned_to": str(i.assigned_to) if i.assigned_to else None,
            "opened_at": iso(i.opened_at), "closed_at": iso(i.closed_at)}


def type_out(t):
    return {"id": str(t.id), "code": t.code, "name": t.name, "icon": t.icon,
            "default_interval_days": t.default_interval_days, "geofence_radius_m": t.geofence_radius_m}


def template_out(t):
    return {"id": str(t.id), "asset_type_id": str(t.asset_type_id), "version": t.version,
            "questions": t.questions, "active": t.active}


def tag_out(t):
    return {"code": t.code, "asset_id": str(t.asset_id) if t.asset_id else None, "active": t.active, "kind": t.kind}


def user_out(u):
    return {"id": str(u.id), "name": u.name, "phone": u.phone, "email": u.email, "role": u.role,
            "zone_ids": [str(z) for z in (u.zone_ids or [])], "language": u.language, "active": u.active}
