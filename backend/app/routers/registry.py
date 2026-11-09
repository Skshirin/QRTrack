import json
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from geoalchemy2 import WKTElement
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..db import get_db
from ..deps import SUPERVISOR_UP, audit, current_user, require, zone_scope
from ..models import Asset, AssetType, ChecklistTemplate, Tag, User, Zone
from ..schemas import asset_out, tag_out, template_out, type_out, user_out
from ..security import hash_pin
from ..services.tagsheet import new_code, sheet_pdf

router = APIRouter(tags=["registry"])


# ---- zones & asset types ------------------------------------------------------------------
@router.get("/zones")
def zones(user: User = Depends(current_user), db: Session = Depends(get_db)):
    q = select(Zone, func.ST_AsGeoJSON(Zone.boundary))
    if zone_scope(user) is not None:
        q = q.where(Zone.id.in_(zone_scope(user)))
    return [{"id": str(z.id), "name": z.name, "boundary": json.loads(gj) if gj else None} for z, gj in db.execute(q)]


class ZoneBody(BaseModel):
    name: str
    site_id: uuid.UUID
    polygon: list[list[float]] | None = None  # [[lng,lat],...] closed ring


@router.post("/zones")
def create_zone(b: ZoneBody, user: User = Depends(require("admin")), db: Session = Depends(get_db)):
    wkt = None
    if b.polygon:
        wkt = WKTElement("POLYGON((" + ",".join(f"{x} {y}" for x, y in b.polygon) + "))", srid=4326)
    z = Zone(name=b.name, site_id=b.site_id, boundary=wkt)
    db.add(z)
    db.flush()
    audit(db, user, "create", "zone", z.id)
    db.commit()
    return {"id": str(z.id)}


@router.get("/asset-types")
def asset_types(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return [type_out(t) for t in db.scalars(select(AssetType).order_by(AssetType.code))]


class TypeBody(BaseModel):
    code: str | None = None
    name: dict | None = None
    icon: str | None = None
    default_interval_days: int | None = None
    geofence_radius_m: int | None = None


@router.post("/asset-types")
def create_type(b: TypeBody, user: User = Depends(require("admin")), db: Session = Depends(get_db)):
    t = AssetType(code=b.code, name=b.name or {"en": b.code}, icon=b.icon or "place",
                  default_interval_days=b.default_interval_days or 7, geofence_radius_m=b.geofence_radius_m or 30)
    db.add(t)
    db.flush()
    audit(db, user, "create", "asset_type", t.id)
    db.commit()
    return type_out(t)


@router.patch("/asset-types/{tid}")
def patch_type(tid: uuid.UUID, b: TypeBody, user: User = Depends(require("admin")), db: Session = Depends(get_db)):
    t = db.get(AssetType, tid)
    if not t:
        raise HTTPException(404)
    for k, v in b.model_dump(exclude_none=True).items():
        setattr(t, k, v)
    audit(db, user, "update", "asset_type", tid, b.model_dump(exclude_none=True))
    db.commit()
    return type_out(t)


# ---- assets -------------------------------------------------------------------------------
@router.get("/assets")
def list_assets(zone_id: uuid.UUID | None = None, type_id: uuid.UUID | None = None, state: str | None = None,
                limit: int = Query(10000, le=20000), user: User = Depends(current_user), db: Session = Depends(get_db)):
    q = select(Asset)
    if zone_scope(user) is not None:
        q = q.where(Asset.zone_id.in_(zone_scope(user)))
    if zone_id:
        q = q.where(Asset.zone_id == zone_id)
    if type_id:
        q = q.where(Asset.type_id == type_id)
    rows = [asset_out(a) for a in db.scalars(q.order_by(Asset.next_due_at).limit(limit))]
    return [r for r in rows if r["state"] == state] if state else rows


class AssetBody(BaseModel):
    id: uuid.UUID | None = None
    type_id: uuid.UUID | None = None
    zone_id: uuid.UUID | None = None
    name: str | None = None
    lat: float | None = None
    lng: float | None = None
    interval_days: int | None = None
    status: str | None = None


@router.post("/assets")
def create_asset(b: AssetBody, user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    atype = db.get(AssetType, b.type_id)
    if not atype or not b.zone_id or b.lat is None or b.lng is None or not b.name:
        raise HTTPException(422, "type_id, zone_id, name, lat, lng are required")
    interval = b.interval_days or atype.default_interval_days
    a = Asset(id=b.id or uuid.uuid4(), type_id=atype.id, zone_id=b.zone_id, name=b.name, lat=b.lat, lng=b.lng,
              location=WKTElement(f"POINT({b.lng} {b.lat})", srid=4326), interval_days=interval,
              next_due_at=datetime.now(timezone.utc) + timedelta(days=interval), created_by=user.id)
    db.add(a)
    db.flush()
    audit(db, user, "create", "asset", a.id)
    db.commit()
    return asset_out(a)


@router.patch("/assets/{aid}")
def patch_asset(aid: uuid.UUID, b: AssetBody, user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    a = db.get(Asset, aid)
    if not a:
        raise HTTPException(404)
    for k, v in b.model_dump(exclude_none=True, exclude={"id"}).items():
        setattr(a, k, v)
    if b.lat is not None and b.lng is not None:
        a.location = WKTElement(f"POINT({b.lng} {b.lat})", srid=4326)
    audit(db, user, "update", "asset", aid, b.model_dump(mode="json", exclude_none=True))
    db.commit()
    return asset_out(a)


class AssignBody(BaseModel):
    asset_ids: list[uuid.UUID]
    user_id: uuid.UUID


@router.post("/assets/assign")
def assign(b: AssignBody, user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    n = 0
    for a in db.scalars(select(Asset).where(Asset.id.in_(b.asset_ids))):
        a.assigned_to = b.user_id
        n += 1
    audit(db, user, "assign", "asset", "bulk", {"count": n, "to": str(b.user_id)})
    db.commit()
    return {"assigned": n}


# ---- checklist templates (data, not code) -------------------------------------------------
@router.get("/checklist-templates")
def templates(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return [template_out(t) for t in db.scalars(select(ChecklistTemplate).order_by(ChecklistTemplate.asset_type_id, ChecklistTemplate.version.desc()))]


class TemplateBody(BaseModel):
    asset_type_id: uuid.UUID
    questions: list[dict]


@router.post("/checklist-templates")
def new_template_version(b: TemplateBody, user: User = Depends(require("admin")), db: Session = Depends(get_db)):
    v = (db.scalar(select(func.max(ChecklistTemplate.version)).where(ChecklistTemplate.asset_type_id == b.asset_type_id)) or 0) + 1
    t = ChecklistTemplate(asset_type_id=b.asset_type_id, version=v, questions=b.questions)
    db.add(t)
    db.flush()
    audit(db, user, "create", "checklist_template", t.id, {"version": v})
    db.commit()
    return template_out(t)


@router.patch("/checklist-templates/{tid}")
def toggle_template(tid: uuid.UUID, active: bool, user: User = Depends(require("admin")), db: Session = Depends(get_db)):
    t = db.get(ChecklistTemplate, tid)
    if not t:
        raise HTTPException(404)
    t.active = active
    audit(db, user, "update", "checklist_template", tid, {"active": active})
    db.commit()
    return template_out(t)


# ---- tags ---------------------------------------------------------------------------------
class BatchBody(BaseModel):
    count: int


@router.post("/tags/batch")
def tag_batch(b: BatchBody, user: User = Depends(require("admin")), db: Session = Depends(get_db)):
    if not 1 <= b.count <= 500:
        raise HTTPException(422, "count must be 1..500")
    codes: list[str] = []
    while len(codes) < b.count:
        c = new_code()
        if c not in codes and not db.scalar(select(Tag.id).where(Tag.code == c)):
            codes.append(c)
    db.add_all([Tag(code=c, active=True) for c in codes])
    audit(db, user, "create", "tag_batch", codes[0], {"count": b.count})
    db.commit()
    return Response(sheet_pdf(codes), media_type="application/pdf",
                    headers={"Content-Disposition": 'attachment; filename="kanha-tags.pdf"', "X-Tag-Count": str(b.count)})


@router.get("/tags")
def list_tags(linked: bool | None = None, user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    q = select(Tag).order_by(Tag.created_at.desc()).limit(2000)
    if linked is True:
        q = q.where(Tag.asset_id.isnot(None))
    if linked is False:
        q = q.where(Tag.asset_id.is_(None))
    return [tag_out(t) for t in db.scalars(q)]


@router.get("/tags/sheet.pdf")
def reprint(codes: str, user: User = Depends(require("admin"))):
    return Response(sheet_pdf([c for c in codes.split(",") if c]), media_type="application/pdf")


class LinkBody(BaseModel):
    asset_id: uuid.UUID


@router.post("/tags/{code}/link")
def link_tag(code: str, b: LinkBody, user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    tag = db.scalar(select(Tag).where(Tag.code == code))
    if not tag or not db.get(Asset, b.asset_id):
        raise HTTPException(404, "tag or asset not found")
    if tag.asset_id and tag.asset_id != b.asset_id and tag.active:
        raise HTTPException(409, "tag already linked to another asset")
    for old in db.scalars(select(Tag).where(Tag.asset_id == b.asset_id, Tag.active, Tag.id != tag.id)):
        old.active = False
    tag.asset_id, tag.active, tag.linked_at = b.asset_id, True, datetime.now(timezone.utc)
    audit(db, user, "link", "tag", code, {"asset_id": str(b.asset_id)})
    db.commit()
    return tag_out(tag)


# ---- users --------------------------------------------------------------------------------
@router.get("/users")
def users(user: User = Depends(require(*SUPERVISOR_UP)), db: Session = Depends(get_db)):
    return [user_out(u) for u in db.scalars(select(User).order_by(User.name))]


class UserBody(BaseModel):
    name: str | None = None
    phone: str | None = None
    email: str | None = None
    role: str | None = None
    zone_ids: list[uuid.UUID] | None = None
    language: str | None = None
    pin: str | None = None
    active: bool | None = None


@router.post("/users")
def create_user(b: UserBody, user: User = Depends(require("admin")), db: Session = Depends(get_db)):
    if b.role not in ("field_staff", "supervisor", "manager", "admin") or not b.phone or not b.name:
        raise HTTPException(422, "name, phone and a valid role are required")
    u = User(name=b.name, phone=b.phone, email=b.email, role=b.role, zone_ids=b.zone_ids or [],
             language=b.language or "en", pin_hash=hash_pin(b.pin) if b.pin else None)
    db.add(u)
    db.flush()
    audit(db, user, "create", "user", u.id, {"role": b.role})
    db.commit()
    return user_out(u)


@router.patch("/users/{uid}")
def patch_user(uid: uuid.UUID, b: UserBody, user: User = Depends(require("admin")), db: Session = Depends(get_db)):
    u = db.get(User, uid)
    if not u:
        raise HTTPException(404)
    data = b.model_dump(exclude_none=True, exclude={"pin"})
    for k, v in data.items():
        setattr(u, k, v)
    if b.pin:
        u.pin_hash = hash_pin(b.pin)
    audit(db, user, "update", "user", uid, {k: str(v) for k, v in data.items()})
    db.commit()
    return user_out(u)
