import uuid

import jwt
import redis
from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .models import AuditLog, User
from .security import decode_token

bearer = HTTPBearer()
rds = redis.Redis.from_url(settings.redis_url, decode_responses=True)
ALL_ZONES_ROLES = ("admin", "manager")
SUPERVISOR_UP = ("supervisor", "manager", "admin")


def current_user(creds: HTTPAuthorizationCredentials = Depends(bearer), db: Session = Depends(get_db)) -> User:
    try:
        uid = decode_token(creds.credentials, "access")
    except jwt.PyJWTError:
        raise HTTPException(401, "invalid or expired token")
    user = db.get(User, uuid.UUID(uid))
    if not user or not user.active:
        raise HTTPException(401, "user disabled")
    return user


def require(*roles: str):
    def dep(user: User = Depends(current_user)) -> User:
        if user.role not in roles:
            raise HTTPException(403, "role not allowed")
        return user
    return dep


def zone_scope(user: User):
    """None = all zones, otherwise the list of zone ids the user may see."""
    return None if user.role in ALL_ZONES_ROLES else list(user.zone_ids or [])


def rate_limit(name: str, limit: int, seconds: int):
    def dep(request: Request):
        key = f"rl:{name}:{request.client.host if request.client else 'x'}"
        try:
            n = rds.incr(key)
            if n == 1:
                rds.expire(key, seconds)
            if n > limit:
                raise HTTPException(429, "too many requests")
        except redis.RedisError:
            pass  # fail open if Redis is down
    return dep


def audit(db: Session, user: User | None, action: str, entity: str, entity_id, details: dict | None = None):
    db.add(AuditLog(user_id=user.id if user else None, action=action, entity=entity,
                    entity_id=str(entity_id), details=details or {}))
