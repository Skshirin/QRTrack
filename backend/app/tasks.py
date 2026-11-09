import uuid

from celery import Celery
from celery.schedules import crontab
from sqlalchemy import func, select

from .config import settings
from .db import SessionLocal
from .models import Asset, Issue, User
from .services import alerts
from .services.reports import weekly_pdf

celery = Celery("kanha", broker=settings.redis_url)
celery.conf.timezone = "Asia/Kolkata"
celery.conf.beat_schedule = {
    "overdue-digest": {"task": "app.tasks.overdue_digest", "schedule": crontab(hour=7, minute=0)},
    "weekly-report": {"task": "app.tasks.weekly_report", "schedule": crontab(hour=7, minute=30, day_of_week=1)},
}


@celery.task
def overdue_digest():
    from datetime import datetime, timezone
    now = datetime.now(timezone.utc)
    with SessionLocal() as db:
        for sup in db.scalars(select(User).where(User.role == "supervisor", User.active)):
            n = db.scalar(select(func.count()).select_from(Asset).where(
                Asset.status == "active", Asset.next_due_at < now, Asset.zone_id.in_(sup.zone_ids or [])))
            if n:
                alerts.notify(db, [sup], f"{n} overdue control points", "Open the dashboard map to see them in red.")


@celery.task
def alert_high_issue(issue_id: str):
    with SessionLocal() as db:
        issue = db.get(Issue, uuid.UUID(issue_id))
        asset = db.get(Asset, issue.asset_id)
        users = [u for u in db.scalars(select(User).where(User.active, User.role.in_(["supervisor", "manager", "admin"])))
                 if u.role != "supervisor" or asset.zone_id in (u.zone_ids or [])]
        alerts.notify(db, users, f"High severity issue: {issue.type}", f"Asset: {asset.name}")


@celery.task
def weekly_report():
    with SessionLocal() as db:
        alerts.send_mail(settings.lab_email, "Kanha QR - weekly summary", "Weekly PDF attached.", weekly_pdf(db), "weekly.pdf")
