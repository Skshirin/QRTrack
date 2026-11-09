import logging
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException
from geoalchemy2 import WKTElement
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import SUPERVISOR_UP, audit, current_user, rate_limit, zone_scope
from ..models import (Asset, AssetType, ChecklistTemplate, Inspection, Issue, Photo, Tag, User, Zone)
from ..schemas import asset_out, iso, issue_out, tag_out, template_out, type_out
from ..services.rules import evaluate, location_flags

router = APIRouter(prefix="/sync", tags=["sync"])
log = logging.getLogger("sync")


class Retry(Exception):
    """Transient problem - the phone keeps the item in its outbox and tries again."""


class PushItem(BaseModel):
    type: str
    id: uuid.UUID
    data: dict = {}


class PushBody(BaseModel):
    device_now: datetime | None = None
    items: list[PushItem]


def dt(v, default=None):
    if not v:
        return default
    d = datetime.fromisoformat(str(v).replace("Z", "+00:00"))
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def point(lat, lng):
    return WKTElement(f"POINT({lng} {lat})", srid=4326)


def can_see_zone(user: User, zone_id) -> bool:
    z = zone_scope(user)
    return z is None or zone_id in z


# ------------------------------------------------------------------ handlers
def h_asset(db, user, it, ctx):
    if user.role not in SUPERVISOR_UP:
        raise HTTPException(403, "only supervisors/admins can create assets")
    if db.get(Asset, it.id):
        return "duplicate"
    d = it.data
    atype = db.get(AssetType, uuid.UUID(d["type_id"])) if d.get("type_id") else \
        db.scalar(select(AssetType).where(AssetType.code == d.get("type_code")))
    if not atype:
        raise HTTPException(422, "unknown asset type")
    zone_id = uuid.UUID(d["zone_id"])
    if not db.get(Zone, zone_id) or not can_see_zone(user, zone_id):
        raise HTTPException(403, "zone not allowed")
    interval = int(d.get("interval_days") or atype.default_interval_days)
    created = dt(d.get("created_at"), ctx["now"])
    db.add(Asset(id=it.id, type_id=atype.id, zone_id=zone_id, name=d["name"], lat=d["lat"], lng=d["lng"],
                 location=point(d["lat"], d["lng"]), interval_days=interval,
                 next_due_at=created + timedelta(days=interval), created_by=user.id))
    audit(db, user, "create", "asset", it.id, {"name": d["name"]})
    return "ok"


def h_tag_link(db, user, it, ctx):
    if user.role not in SUPERVISOR_UP:
        raise HTTPException(403, "only supervisors/admins can link tags")
    code, asset_id = it.data["tag_code"], uuid.UUID(it.data["asset_id"])
    tag = db.scalar(select(Tag).where(Tag.code == code))
    if not tag:
        raise HTTPException(404, "unknown tag code")
    if not db.get(Asset, asset_id):
        raise Retry("asset not synced yet")
    if tag.asset_id == asset_id and tag.active:
        return "duplicate"
    if tag.asset_id and tag.asset_id != asset_id and tag.active:
        raise HTTPException(409, "tag already linked to another asset")
    for old in db.scalars(select(Tag).where(Tag.asset_id == asset_id, Tag.active)):
        old.active = False  # damaged tag replaced: history stays
    tag.asset_id, tag.active, tag.linked_at = asset_id, True, ctx["now"]
    audit(db, user, "link", "tag", code, {"asset_id": str(asset_id)})
    return "ok"


def h_inspection(db, user, it, ctx):
    if db.get(Inspection, it.id):
        return "duplicate"
    d = it.data
    tag_code, flags, asset = d.get("tag_code"), [], None
    if tag_code:
        tag = db.scalar(select(Tag).where(Tag.code == tag_code))
        if tag and tag.asset_id:
            asset = db.get(Asset, tag.asset_id)
            if not tag.active:
                flags.append("inactive_tag")
    if not asset and d.get("asset_id"):
        asset = db.get(Asset, uuid.UUID(d["asset_id"]))
    if not asset:
        flags.append("unknown_tag")
    elif not can_see_zone(user, asset.zone_id):
        flags.append("outside_zone")
    scanned_at = dt(d.get("scanned_at"), ctx["now"])
    lat, lng, acc = d.get("gps_lat"), d.get("gps_lng"), d.get("gps_accuracy_m")
    dist = None
    if asset and lat is not None and lng is not None:  # distance is recomputed here, never trusted from the phone
        dist = db.scalar(select(func.ST_Distance(Asset.location, func.ST_GeogFromText(f"SRID=4326;POINT({lng} {lat})")))
                         .where(Asset.id == asset.id))
    radius, questions, version = 30, [], None
    if asset:
        atype = db.get(AssetType, asset.type_id)
        radius = atype.geofence_radius_m
        q = select(ChecklistTemplate).where(ChecklistTemplate.asset_type_id == atype.id)
        if d.get("template_version"):
            q = q.where(ChecklistTemplate.version == int(d["template_version"]))
        tpl = db.scalar(q.order_by(ChecklistTemplate.version.desc()))
        if tpl:
            questions, version = tpl.questions, tpl.version
    flags += location_flags(dist, acc, radius, bool(d.get("is_mocked")), d.get("scan_method") == "manual")
    if ctx["skew"]:
        flags.append("clock_skew")
    answers = d.get("answers") or {}
    fails = evaluate(questions, answers)
    db.add(Inspection(
        id=it.id, asset_id=asset.id if asset else None, tag_code=tag_code, user_id=user.id, template_version=version,
        answers=answers, result="fail" if fails else "pass", scanned_at=scanned_at,
        device_time=dt(d.get("device_time"), scanned_at), gps=point(lat, lng) if lat is not None and lng is not None else None,
        gps_lat=lat, gps_lng=lng, gps_accuracy_m=acc, distance_from_asset_m=dist, is_mocked=bool(d.get("is_mocked")),
        scan_method=d.get("scan_method", "qr"), flags=flags))
    db.flush()
    for f in fails:  # deterministic id => retrying the same inspection never duplicates issues
        iid = uuid.uuid5(it.id, f["key"])
        db.add(Issue(id=iid, asset_id=asset.id, inspection_id=it.id, type=f["key"], severity=f["severity"]))
        if f["severity"] == "high":
            ctx["high"].append(str(iid))
    if asset and (asset.last_inspected_at is None or scanned_at > asset.last_inspected_at):
        asset.last_inspected_at = scanned_at
        asset.next_due_at = scanned_at + timedelta(days=asset.interval_days)
    return "ok"


def h_photo(db, user, it, ctx):
    if db.get(Photo, it.id):
        return "duplicate"
    d = it.data
    insp_id = uuid.UUID(d["inspection_id"]) if d.get("inspection_id") else None
    issue_id = uuid.UUID(d["issue_id"]) if d.get("issue_id") else None
    insp = db.get(Inspection, insp_id) if insp_id else None
    issue = db.get(Issue, issue_id) if issue_id else None
    if insp_id and not insp and not issue:
        if insp_id in ctx.get("rejected_parents", set()):
            raise HTTPException(422, "parent inspection was rejected")
        raise Retry("parent record not synced yet")
    if issue_id and not issue and not insp:
        if issue_id in ctx.get("rejected_parents", set()):
            raise HTTPException(422, "parent issue was rejected")
        raise Retry("parent record not synced yet")
    if not (insp_id or issue_id):
        raise HTTPException(422, "parent record required")
    db.add(Photo(id=it.id, inspection_id=insp_id, issue_id=issue_id, kind=d.get("kind", "evidence"),
                 storage_key=f"photos/{it.id}.jpg", sha256=d["sha256"], taken_at=dt(d.get("taken_at"), ctx["now"]),
                 gps_lat=d.get("gps_lat"), gps_lng=d.get("gps_lng"), width=d.get("width"), height=d.get("height"),
                 uploaded_by=user.id))
    if insp and db.scalar(select(func.count()).select_from(Photo).where(Photo.sha256 == d["sha256"], Photo.id != it.id)):
        insp.flags = [*insp.flags, "duplicate_photo"]
    return "ok"


def h_issue(db, user, it, ctx):  # raised by hand
    if db.get(Issue, it.id):
        return "duplicate"
    d = it.data
    asset = db.get(Asset, uuid.UUID(d["asset_id"]))
    if not asset:
        raise HTTPException(404, "asset not found")
    db.add(Issue(id=it.id, asset_id=asset.id, type=d.get("type", "manual"), severity=d.get("severity", "medium"), note=d.get("note")))
    if d.get("severity") == "high":
        ctx["high"].append(str(it.id))
    return "ok"


FLOW = {"open": {"assigned", "fixed"}, "assigned": {"fixed", "open"}, "fixed": {"verified", "assigned"}, "verified": set()}


def apply_issue_update(db, user, issue: Issue, status=None, assigned_to=None, note=None):
    """Shared by the phone (sync) and the dashboard (PATCH /issues/{id})."""
    if assigned_to is not None:
        if user.role not in SUPERVISOR_UP:
            raise HTTPException(403, "only supervisors can assign")
        issue.assigned_to = uuid.UUID(str(assigned_to))
        if issue.status == "open" and not status:
            status = "assigned"
    if status and status != issue.status:
        if status not in FLOW[issue.status]:
            raise HTTPException(409, f"server version wins: issue is already '{issue.status}'")
        if status == "assigned" and user.role not in SUPERVISOR_UP:
            raise HTTPException(403, "only supervisors can assign")
        if status == "fixed":
            if user.role not in SUPERVISOR_UP and issue.assigned_to and issue.assigned_to != user.id:
                raise HTTPException(403, "only the assignee can fix this issue")
            if not issue.assigned_to:
                issue.assigned_to = user.id
            if not db.scalar(select(func.count()).select_from(Photo).where(Photo.issue_id == issue.id, Photo.kind == "after")):
                raise HTTPException(422, "an after-photo is required to mark an issue fixed")
        if status == "verified":
            if user.role not in ("manager", "admin"):
                raise HTTPException(403, "only managers can close issues")
            issue.closed_at = datetime.now(timezone.utc)
        issue.status = status
    if note:
        issue.note = note
    audit(db, user, "update", "issue", issue.id, {"status": issue.status, "assigned_to": str(issue.assigned_to)})


def h_issue_update(db, user, it, ctx):
    issue = db.get(Issue, uuid.UUID(it.data["issue_id"]))
    if not issue:
        raise Retry("issue not synced yet")
    apply_issue_update(db, user, issue, it.data.get("status"), it.data.get("assigned_to"), it.data.get("note"))
    return "ok"


HANDLERS = {"asset": h_asset, "tag_link": h_tag_link, "inspection": h_inspection, "photo": h_photo,
            "issue": h_issue, "issue_update": h_issue_update}
ORDER = ["asset", "tag_link", "inspection", "issue", "photo", "issue_update"]  # parents before children


@router.post("/push", dependencies=[Depends(rate_limit("sync", 120, 60))])
def push(body: PushBody, user: User = Depends(current_user), db: Session = Depends(get_db)):
    now = datetime.now(timezone.utc)
    skew = bool(body.device_now) and abs((now - dt(body.device_now)).total_seconds()) > 300
    ctx = {"now": now, "skew": skew, "high": []}
    results = []
    for it in sorted(body.items, key=lambda i: ORDER.index(i.type) if i.type in ORDER else 99):
        res = {"id": str(it.id), "type": it.type}
        handler = HANDLERS.get(it.type)
        if not handler:
            results.append({**res, "status": "rejected", "detail": "unknown item type"})
            continue
        try:
            with db.begin_nested():  # a failing item rolls back alone
                res["status"] = handler(db, user, it, ctx)
        except HTTPException as e:
            ctx.setdefault("rejected_parents", set()).add(it.id)
            res.update(status="rejected", detail=str(e.detail))
        except Retry as e:
            res.update(status="retry", detail=str(e))
        except Exception as e:  # noqa: BLE001
            log.exception("sync item failed")
            res.update(status="retry", detail=type(e).__name__)
        results.append(res)
    db.commit()
    if ctx["high"]:
        try:
            from ..tasks import alert_high_issue
            for i in ctx["high"]:
                alert_high_issue.delay(i)
        except Exception:  # noqa: BLE001
            log.warning("could not queue alerts")
    return {"results": results, "server_time": iso(now)}


@router.get("/pull", dependencies=[Depends(rate_limit("pull", 120, 60))])
def pull(since: str | None = None, user: User = Depends(current_user), db: Session = Depends(get_db)):
    now = datetime.now(timezone.utc)
    since_dt = dt(since) - timedelta(seconds=10) if since else None  # small overlap; phone upserts are idempotent
    scope = zone_scope(user)

    def newer(q, col):
        return q.where(col > since_dt) if since_dt else q

    zq = newer(select(Zone), Zone.updated_at)
    aq = newer(select(Asset), Asset.updated_at)
    iq = newer(select(Issue).join(Asset, Asset.id == Issue.asset_id), Issue.updated_at)
    if scope is not None:
        zq, aq, iq = zq.where(Zone.id.in_(scope)), aq.where(Asset.zone_id.in_(scope)), iq.where(Asset.zone_id.in_(scope))
    tq = newer(select(Tag).outerjoin(Asset, Asset.id == Tag.asset_id), Tag.updated_at)
    if scope is not None:
        tq = tq.where(Asset.zone_id.in_(scope)) if user.role not in SUPERVISOR_UP else tq.where((Asset.zone_id.in_(scope)) | (Tag.asset_id.is_(None)))
    return {
        "token": iso(now),
        "full": since is None,
        "zones": [{"id": str(z.id), "name": z.name} for z in db.scalars(zq)],
        "asset_types": [type_out(t) for t in db.scalars(newer(select(AssetType), AssetType.updated_at))],
        "templates": [template_out(t) for t in db.scalars(newer(select(ChecklistTemplate), ChecklistTemplate.updated_at))],
        "assets": [asset_out(a) for a in db.scalars(aq)],
        "tags": [tag_out(t) for t in db.scalars(tq)],
        "issues": [issue_out(i) for i in db.scalars(iq)],
        "users": [{"id": str(u.id), "name": u.name, "role": u.role} for u in db.scalars(select(User).where(User.active))],
    }
