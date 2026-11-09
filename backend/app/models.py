import uuid
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def pk():
    return mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)


def created():
    return mapped_column(DateTime(timezone=True), server_default=func.now())


def updated():
    return mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), index=True)


def fk(table, nullable=True, **kw):
    return mapped_column(UUID(as_uuid=True), ForeignKey(f"{table}.id"), nullable=nullable, **kw)


# ---- shared with Sentinel: site, zone, user, audit_log ----------------------------------
class Site(Base):
    __tablename__ = "site"
    id: Mapped[uuid.UUID] = pk()
    name: Mapped[str] = mapped_column(String(200))
    boundary = mapped_column(Geography("POLYGON", 4326), nullable=True)


class Zone(Base):
    __tablename__ = "zone"
    id: Mapped[uuid.UUID] = pk()
    site_id = fk("site", nullable=False)
    name: Mapped[str] = mapped_column(String(200))
    boundary = mapped_column(Geography("POLYGON", 4326), nullable=True)
    updated_at: Mapped[datetime] = updated()


class User(Base):
    __tablename__ = "user"
    id: Mapped[uuid.UUID] = pk()
    name: Mapped[str] = mapped_column(String(200))
    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    email: Mapped[str | None] = mapped_column(String(200), nullable=True)
    role: Mapped[str] = mapped_column(String(20))  # field_staff | supervisor | manager | admin
    zone_ids = mapped_column(ARRAY(UUID(as_uuid=True)), default=list)
    language: Mapped[str] = mapped_column(String(5), default="en")
    pin_hash: Mapped[str | None] = mapped_column(String(200), nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = created()


class AuditLog(Base):
    __tablename__ = "audit_log"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id = mapped_column(UUID(as_uuid=True), nullable=True)
    action: Mapped[str] = mapped_column(String(50))
    entity: Mapped[str] = mapped_column(String(50))
    entity_id: Mapped[str] = mapped_column(String(64))
    at: Mapped[datetime] = created()
    details = mapped_column(JSONB, default=dict)


class Notification(Base):
    __tablename__ = "notification"
    id: Mapped[uuid.UUID] = pk()
    user_id = fk("user", nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200))
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = created()
    read_at = mapped_column(DateTime(timezone=True), nullable=True)


# ---- QR module -----------------------------------------------------------------------------
class AssetType(Base):
    __tablename__ = "asset_type"
    id: Mapped[uuid.UUID] = pk()
    code: Mapped[str] = mapped_column(String(40), unique=True)
    name = mapped_column(JSONB)  # {"en":..,"te":..,"hi":..}
    icon: Mapped[str] = mapped_column(String(40), default="place")
    default_interval_days: Mapped[int] = mapped_column(Integer, default=7)
    geofence_radius_m: Mapped[int] = mapped_column(Integer, default=30)
    updated_at: Mapped[datetime] = updated()


class Asset(Base):
    __tablename__ = "asset"
    id: Mapped[uuid.UUID] = pk()  # may be generated on the phone
    type_id = fk("asset_type", nullable=False)
    zone_id = fk("zone", nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(200))
    location = mapped_column(Geography("POINT", 4326))
    lat: Mapped[float] = mapped_column(Float)
    lng: Mapped[float] = mapped_column(Float)
    status: Mapped[str] = mapped_column(String(20), default="active")  # active | retired
    interval_days: Mapped[int] = mapped_column(Integer, default=7)
    next_due_at = mapped_column(DateTime(timezone=True), index=True)
    last_inspected_at = mapped_column(DateTime(timezone=True), nullable=True)
    assigned_to = fk("user")
    created_by = fk("user")
    created_at: Mapped[datetime] = created()
    updated_at: Mapped[datetime] = updated()


class Tag(Base):
    __tablename__ = "tag"
    id: Mapped[uuid.UUID] = pk()
    code: Mapped[str] = mapped_column(String(20), unique=True, index=True)
    asset_id = fk("asset", index=True)
    kind: Mapped[str] = mapped_column(String(10), default="qr")
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = created()
    linked_at = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at: Mapped[datetime] = updated()


class ChecklistTemplate(Base):
    __tablename__ = "checklist_template"
    __table_args__ = (UniqueConstraint("asset_type_id", "version"),)
    id: Mapped[uuid.UUID] = pk()
    asset_type_id = fk("asset_type", nullable=False)
    version: Mapped[int] = mapped_column(Integer)
    questions = mapped_column(JSONB)
    active: Mapped[bool] = mapped_column(Boolean, default=True)
    updated_at: Mapped[datetime] = updated()


class Inspection(Base):
    __tablename__ = "inspection"
    id: Mapped[uuid.UUID] = pk()  # client UUID
    asset_id = fk("asset", index=True)
    tag_code: Mapped[str | None] = mapped_column(String(20), nullable=True)
    user_id = fk("user", nullable=False, index=True)
    template_version: Mapped[int | None] = mapped_column(Integer, nullable=True)
    answers = mapped_column(JSONB, default=dict)
    result: Mapped[str] = mapped_column(String(10))  # pass | fail
    scanned_at = mapped_column(DateTime(timezone=True), index=True)
    device_time = mapped_column(DateTime(timezone=True))
    synced_at = mapped_column(DateTime(timezone=True), server_default=func.now())  # server receive time
    gps = mapped_column(Geography("POINT", 4326), nullable=True)
    gps_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    gps_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    gps_accuracy_m: Mapped[float | None] = mapped_column(Float, nullable=True)
    distance_from_asset_m: Mapped[float | None] = mapped_column(Float, nullable=True)  # computed by the SERVER
    is_mocked: Mapped[bool] = mapped_column(Boolean, default=False)
    scan_method: Mapped[str] = mapped_column(String(10), default="qr")
    flags = mapped_column(JSONB, default=list)
    review_status: Mapped[str] = mapped_column(String(10), default="pending")  # pending|approved|rejected
    reviewed_by = fk("user")
    reviewed_at = mapped_column(DateTime(timezone=True), nullable=True)
    review_note: Mapped[str | None] = mapped_column(Text, nullable=True)


class Photo(Base):
    __tablename__ = "photo"
    id: Mapped[uuid.UUID] = pk()  # client UUID
    inspection_id = fk("inspection", index=True)
    issue_id = fk("issue", index=True)
    kind: Mapped[str] = mapped_column(String(10), default="evidence")  # evidence | before | after
    storage_key: Mapped[str] = mapped_column(String(200))
    sha256: Mapped[str] = mapped_column(String(64), index=True)
    taken_at = mapped_column(DateTime(timezone=True))
    gps_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    gps_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    width: Mapped[int | None] = mapped_column(Integer, nullable=True)
    height: Mapped[int | None] = mapped_column(Integer, nullable=True)
    size_bytes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    confirmed_at = mapped_column(DateTime(timezone=True), nullable=True)
    uploaded_by = fk("user")
    created_at: Mapped[datetime] = created()


class Issue(Base):
    __tablename__ = "issue"
    id: Mapped[uuid.UUID] = pk()
    asset_id = fk("asset", nullable=False, index=True)
    inspection_id = fk("inspection")
    type: Mapped[str] = mapped_column(String(80))
    severity: Mapped[str] = mapped_column(String(10), default="medium")  # low|medium|high
    status: Mapped[str] = mapped_column(String(10), default="open")  # open|assigned|fixed|verified
    assigned_to = fk("user")
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    opened_at: Mapped[datetime] = created()
    closed_at = mapped_column(DateTime(timezone=True), nullable=True)
    updated_at: Mapped[datetime] = updated()
