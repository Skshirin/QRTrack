import hashlib
import hmac
import os
from datetime import datetime, timedelta, timezone

import jwt

from .config import settings


def hash_pin(pin: str) -> str:
    salt = os.urandom(16)
    h = hashlib.pbkdf2_hmac("sha256", pin.encode(), salt, 200_000)
    return f"{salt.hex()}${h.hex()}"


def check_pin(pin: str, stored: str | None) -> bool:
    if not stored:
        return False
    salt, h = stored.split("$")
    cand = hashlib.pbkdf2_hmac("sha256", pin.encode(), bytes.fromhex(salt), 200_000).hex()
    return hmac.compare_digest(cand, h)


def make_token(user_id, kind: str) -> str:
    delta = timedelta(minutes=settings.access_minutes) if kind == "access" else timedelta(days=settings.refresh_days)
    payload = {"sub": str(user_id), "typ": kind, "exp": datetime.now(timezone.utc) + delta}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def decode_token(token: str, kind: str) -> str:
    data = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
    if data.get("typ") != kind:
        raise jwt.InvalidTokenError("wrong token type")
    return data["sub"]
