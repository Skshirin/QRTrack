import csv
import io
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import SUPERVISOR_UP, audit, current_user, require, zone_scope
from ..models import Asset, Inspection, Issue, Notification, Photo, User
from ..schemas import issue_out, iso
from ..services import reports, storage
from .sync import apply_issue_update

router = APIRouter(tags=["ops"])


def photos_for(db, insp_ids=(), issue_ids=()):
    out: dict = {}
    q = select(Photo).where((Photo.inspection_id.in_(list(insp_ids))) | (Photo.issue_id.in_(list(issue_ids))))
    for p in db.scalars(q):
        if not p.confirmed_at:
            continue
        key = p.inspection_id or p.issue_id
        out.setdefault(key, []).append({"id": str(p.id), "kind": p.kind, "url": storage.presign_get(p.storage_key),
                                        "taken_at": iso(p.taken_at)})
    return out


# ---- inspections --------------------------------------------------------------------------
@router.get("/inspections")
def inspections(asset_id: uuid.UUID | None = None, zone_id: uuid.UUID | None = None, flagged: bool | None = None,
                review_status: str | None = None, date_from: datetime | None = None, date_to: datetime | None = None,
                limit: int = Query(100, le=500), user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    q = select(Inspection, Asset.name, User.name).outerjoin(Asset, Asset.id == Inspection.asset_id).join(User, User.id == Inspection.user_id)
    if zone_scope(user) is not None:
        q = q.where(Asset.zone_id.in_(zone_scope(user)))
    if asset_id:
        q = q.where(Inspection.asset_id == asset_id)
    if zone_id:
        q = q.where(Asset.zone_id == zone_id)
    if flagged:
        q = q.where(func.jsonb_array_length(Inspection.flags) > 0)
    if review_status:
        q = q.where(Inspection.review_status == review_status)
    if date_from:
        q = q.where(Inspection.scanned_at >= date_from)
    if date_to:
        q = q.where(Inspection.scanned_at <= date_to)
    rows = db.execute(q.order_by(Inspection.scanned_at.desc()).limit(limit)).all()
    ph = photos_for(db, insp_ids=[r[0].id for r in rows])
    return [{"id": str(i.id), "asset_id": str(i.asset_id) if i.asset_id else None, "asset_name": an, "user_name": un,
             "scanned_at": iso(i.scanned_at), "synced_at": iso(i.synced_at), "result": i.result, "flags": i.flags,
             "distance_m": i.distance_from_asset_m, "accuracy_m": i.gps_accuracy_m, "is_mocked": i.is_mocked,
             "scan_method": i.scan_method, "review_status": i.review_status, "review_note": i.review_note,
             "answers": i.answers, "photos": ph.get(i.id, [])} for i, an, un in rows]


class ReviewBody(BaseModel):
    decision: str  # approved | rejected
    note: str | None = None


@router.patch("/inspections/{iid}/review")
def review(iid: uuid.UUID, b: ReviewBody, user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    i = db.get(Inspection, iid)
    if not i or b.decision not in ("approved", "rejected"):
        raise HTTPException(422, "bad request")
    i.review_status, i.reviewed_by, i.reviewed_at, i.review_note = b.decision, user.id, datetime.now(timezone.utc), b.note
    if b.decision == "rejected" and i.asset_id:  # evidence rejected -> the asset is due again
        a = db.get(Asset, i.asset_id)
        a.next_due_at = datetime.now(timezone.utc)
    audit(db, user, "review", "inspection", iid, {"decision": b.decision})
    db.commit()
    return {"ok": True}


# ---- issues -------------------------------------------------------------------------------
@router.get("/issues")
def issues(status: str | None = None, user: User = Depends(current_user), db: Session = Depends(get_db)):
    q = select(Issue, Asset.name).join(Asset, Asset.id == Issue.asset_id)
    if zone_scope(user) is not None:
        q = q.where(Asset.zone_id.in_(zone_scope(user)))
    if status:
        q = q.where(Issue.status == status)
    rows = db.execute(q.order_by(Issue.opened_at.desc()).limit(300)).all()
    ph = photos_for(db, insp_ids=[i.inspection_id for i, _ in rows if i.inspection_id], issue_ids=[i.id for i, _ in rows])
    out = []
    for i, an in rows:
        photos = ph.get(i.id, []) + ph.get(i.inspection_id, [])
        out.append({**issue_out(i), "asset_name": an, "photos": photos})
    return out


class IssueBody(BaseModel):
    status: str | None = None
    assigned_to: uuid.UUID | None = None
    note: str | None = None


@router.patch("/issues/{iid}")
def patch_issue(iid: uuid.UUID, b: IssueBody, user: User = Depends(current_user), db: Session = Depends(get_db)):
    issue = db.get(Issue, iid)
    if not issue:
        raise HTTPException(404)
    apply_issue_update(db, user, issue, b.status, b.assigned_to, b.note)
    db.commit()
    return issue_out(issue)


# ---- notifications ------------------------------------------------------------------------
@router.get("/notifications")
def notifications(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.scalars(select(Notification).where(Notification.user_id == user.id).order_by(Notification.created_at.desc()).limit(50))
    return [{"id": str(n.id), "title": n.title, "body": n.body, "created_at": iso(n.created_at), "read": n.read_at is not None} for n in rows]


@router.post("/notifications/{nid}/read")
def read_notification(nid: uuid.UUID, user: User = Depends(current_user), db: Session = Depends(get_db)):
    n = db.get(Notification, nid)
    if n and n.user_id == user.id:
        n.read_at = datetime.now(timezone.utc)
        db.commit()
    return {"ok": True}


# ---- reports & export ---------------------------------------------------------------------
@router.get("/reports/overview")
def overview(weeks: int = 1, user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    return reports.overview(db, zone_scope(user), weeks)


@router.get("/reports/compliance")
def compliance(date_from: datetime, date_to: datetime, user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    return reports.compliance(db, date_from, date_to, zone_scope(user))


@router.get("/reports/staff")
def staff_activity(days: int = 7, user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    since = datetime.now(timezone.utc) - timedelta(days=days)
    day = func.date(Inspection.scanned_at)
    rows = db.execute(select(User.name, day, func.count()).join(User, User.id == Inspection.user_id)
                      .where(Inspection.scanned_at >= since).group_by(User.name, day).order_by(day.desc(), User.name)).all()
    return [{"user": n, "day": d.isoformat(), "inspections": c} for n, d, c in rows]


@router.get("/reports/weekly.pdf")
def weekly(user: User = Depends(require("manager", "admin")), db: Session = Depends(get_db)):
    return Response(reports.weekly_pdf(db), media_type="application/pdf",
                    headers={"Content-Disposition": 'attachment; filename="kanha-weekly.pdf"'})


@router.get("/export.csv")
def export_csv(date_from: datetime | None = None, date_to: datetime | None = None,
               user: User = Depends(require("manager", "admin")), db: Session = Depends(get_db)):
    q = select(Inspection, Asset.name, User.name).outerjoin(Asset, Asset.id == Inspection.asset_id).join(User, User.id == Inspection.user_id)
    if date_from:
        q = q.where(Inspection.scanned_at >= date_from)
    if date_to:
        q = q.where(Inspection.scanned_at <= date_to)
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["id", "asset", "inspector", "scanned_at", "result", "distance_m", "accuracy_m", "mocked", "scan_method", "flags", "review"])
    for i, an, un in db.execute(q.order_by(Inspection.scanned_at)):
        w.writerow([i.id, an, un, iso(i.scanned_at), i.result, i.distance_from_asset_m, i.gps_accuracy_m,
                    i.is_mocked, i.scan_method, "|".join(i.flags or []), i.review_status])
    return Response(buf.getvalue(), media_type="text/csv", headers={"Content-Disposition": 'attachment; filename="kanha-export.csv"'})
