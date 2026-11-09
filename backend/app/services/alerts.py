"""Alerts go through a channel interface so WhatsApp can be added later without touching callers."""
import logging
import smtplib
from email.message import EmailMessage
from typing import Protocol

from sqlalchemy.orm import Session

from ..config import settings
from ..models import Notification, User

log = logging.getLogger("alerts")


def send_mail(to: str, subject: str, body: str, attachment: bytes | None = None, filename: str = "report.pdf"):
    if not settings.smtp_host:
        log.warning("SMTP not configured - email to %s skipped: %s", to, subject)
        return
    msg = EmailMessage()
    msg["From"], msg["To"], msg["Subject"] = settings.mail_from, to, subject
    msg.set_content(body)
    if attachment:
        msg.add_attachment(attachment, maintype="application", subtype="pdf", filename=filename)
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as s:
        s.starttls()
        if settings.smtp_user:
            s.login(settings.smtp_user, settings.smtp_password)
        s.send_message(msg)


class Channel(Protocol):
    def send(self, db: Session, user: User, title: str, body: str) -> None: ...


class InAppChannel:
    def send(self, db, user, title, body):
        db.add(Notification(user_id=user.id, title=title, body=body))


class EmailChannel:
    def send(self, db, user, title, body):
        if user.email:
            send_mail(user.email, title, body)


# class WhatsAppChannel: implement send() with Meta Cloud API templates once Kanha confirms.
CHANNELS: list[Channel] = [InAppChannel(), EmailChannel()]


def notify(db: Session, users: list[User], title: str, body: str):
    for u in users:
        for ch in CHANNELS:
            try:
                ch.send(db, u, title, body)
            except Exception:  # one failing channel must not block the others
                log.exception("alert channel failed")
    db.commit()
