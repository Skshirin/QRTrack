import io
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from ..models import Asset, AssetType, Inspection, Issue, Zone
from .rules import asset_cycles


def compliance(db: Session, start: datetime, end: datetime, zone_ids=None):
    """compliance % = assets inspected on time in the period / assets due in the period
    (counted per due cycle, see rules.asset_cycles)."""
    q = select(Asset.id, Asset.zone_id, Asset.type_id, Asset.interval_days, Asset.created_at).where(
        Asset.status == "active", Asset.created_at <= end)
    if zone_ids is not None:
        q = q.where(Asset.zone_id.in_(zone_ids))
    assets = db.execute(q).all()
    last_before = dict(db.execute(
        select(Inspection.asset_id, func.max(Inspection.scanned_at))
        .where(Inspection.scanned_at < start, Inspection.review_status != "rejected", Inspection.asset_id.isnot(None))
        .group_by(Inspection.asset_id)).all())
    in_period = defaultdict(list)
    for aid, t in db.execute(select(Inspection.asset_id, Inspection.scanned_at).where(
            Inspection.scanned_at >= start, Inspection.scanned_at <= end,
            Inspection.review_status != "rejected", Inspection.asset_id.isnot(None))):
        in_period[aid].append(t)
    zone, typ, tot = defaultdict(lambda: [0, 0]), defaultdict(lambda: [0, 0]), [0, 0]
    for a in assets:
        prev = last_before.get(a.id) or max(a.created_at, start - timedelta(days=a.interval_days))
        d, ok = asset_cycles(prev, in_period.get(a.id, []), a.interval_days, end)
        for bucket in (zone[a.zone_id], typ[a.type_id], tot):
            bucket[0] += d
            bucket[1] += ok
    pct = lambda b: round(100 * b[1] / b[0], 1) if b[0] else None
    return {
        "overall": {"due": tot[0], "ok": tot[1], "pct": pct(tot)},
        "by_zone": {str(k): {"due": v[0], "ok": v[1], "pct": pct(v)} for k, v in zone.items()},
        "by_type": {str(k): {"due": v[0], "ok": v[1], "pct": pct(v)} for k, v in typ.items()},
    }


def overview(db: Session, zone_ids=None, weeks: int = 1):
    now = datetime.now(timezone.utc)
    day0 = now.replace(hour=0, minute=0, second=0, microsecond=0)
    cur = compliance(db, now - timedelta(days=7 * weeks), now, zone_ids)
    zones = {str(z.id): z.name for z in db.scalars(select(Zone))}
    types = {str(t.id): t.name.get("en", t.code) for t in db.scalars(select(AssetType))}
    for k, v in cur["by_zone"].items():
        v["name"] = zones.get(k, k)
    for k, v in cur["by_type"].items():
        v["name"] = types.get(k, k)
    aq = select(func.count()).select_from(Asset).where(Asset.status == "active", Asset.next_due_at < now)
    iq = select(func.count()).select_from(Issue).where(Issue.status != "verified")
    nq = select(func.count()).select_from(Inspection).where(Inspection.scanned_at >= day0)
    fq = select(func.count()).select_from(Inspection).where(
        Inspection.scanned_at >= now - timedelta(days=7), Inspection.review_status == "pending",
        func.jsonb_array_length(Inspection.flags) > 0)
    if zone_ids is not None:
        aq = aq.where(Asset.zone_id.in_(zone_ids))
    trend = []
    for w in range(11, -1, -1):
        e = now - timedelta(days=7 * w)
        trend.append({"week_end": e.date().isoformat(), "pct": compliance(db, e - timedelta(days=7), e, zone_ids)["overall"]["pct"]})
    return {**cur, "overdue": db.scalar(aq), "open_issues": db.scalar(iq),
            "inspections_today": db.scalar(nq), "flagged": db.scalar(fq), "trend": trend}


def weekly_pdf(db: Session) -> bytes:
    data = overview(db)
    now = datetime.now(timezone.utc)
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    W, H = A4
    y = H - 25 * mm
    c.setFont("Helvetica-Bold", 16)
    c.drawString(20 * mm, y, "Kanha QR Monitoring - Weekly summary")
    c.setFont("Helvetica", 10)
    y -= 8 * mm
    c.drawString(20 * mm, y, f"Week ending {now:%d %b %Y}")
    lines = [
        f"Compliance (last 7 days): {data['overall']['pct']}%  ({data['overall']['ok']} of {data['overall']['due']} due checks on time)",
        f"Overdue assets now: {data['overdue']}",
        f"Open issues: {data['open_issues']}",
        f"Flagged inspections awaiting review: {data['flagged']}",
        "", "By zone:",
    ] + [f"   {v['name']}: {v['pct']}%  ({v['ok']}/{v['due']})" for v in data["by_zone"].values()] + ["", "By asset type:"] + \
        [f"   {v['name']}: {v['pct']}%  ({v['ok']}/{v['due']})" for v in data["by_type"].values()]
    for ln in lines:
        y -= 7 * mm
        c.drawString(20 * mm, y, ln)
    y -= 12 * mm
    c.setFont("Helvetica-Bold", 11)
    c.drawString(20 * mm, y, "Most overdue assets")
    c.setFont("Helvetica", 9)
    rows = db.execute(select(Asset.name, Zone.name, Asset.next_due_at).join(Zone, Zone.id == Asset.zone_id)
                      .where(Asset.status == "active", Asset.next_due_at < now).order_by(Asset.next_due_at).limit(25)).all()
    for name, zname, due in rows:
        y -= 5.5 * mm
        c.drawString(22 * mm, y, f"{name} ({zname}) - {(now - due).days} days overdue")
    c.save()
    return buf.getvalue()
