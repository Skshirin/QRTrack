import logging
import secrets
import uuid

import jwt
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..deps import audit, current_user, rate_limit, rds
from ..models import User
from ..schemas import user_out
from ..security import check_pin, decode_token, make_token

router = APIRouter(prefix="/auth", tags=["auth"])
log = logging.getLogger("auth")


class PhoneBody(BaseModel):
    phone: str


class VerifyBody(BaseModel):
    phone: str
    code: str  # the PIN set by the admin OR the one-time code sent by SMS


class RefreshBody(BaseModel):
    refresh: str


@router.post("/otp", dependencies=[Depends(rate_limit("otp", 10, 3600))])
def request_otp(body: PhoneBody, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.phone == body.phone, User.active))
    resp = {"sent": True}  # same answer whether or not the phone exists
    if user:
        otp = f"{secrets.randbelow(10**6):06d}"
        rds.setex(f"otp:{body.phone}", 300, otp)
        log.warning("OTP for %s is %s (plug an SMS provider in here)", body.phone, otp)
        if settings.dev_otp_echo:
            resp["dev_otp"] = otp
    return resp


@router.post("/verify", dependencies=[Depends(rate_limit("verify", 30, 60))])
def verify(body: VerifyBody, db: Session = Depends(get_db)):
    fails_key = f"fails:{body.phone}"
    if int(rds.get(fails_key) or 0) >= 10:
        raise HTTPException(429, "too many attempts, try again in 15 minutes")
    user = db.scalar(select(User).where(User.phone == body.phone, User.active))
    otp = rds.get(f"otp:{body.phone}")
    ok = bool(user) and (check_pin(body.code, user.pin_hash) or (otp is not None and secrets.compare_digest(otp, body.code)))
    if not ok:
        rds.incr(fails_key)
        rds.expire(fails_key, 900)
        raise HTTPException(401, "wrong phone or code")
    rds.delete(fails_key, f"otp:{body.phone}")
    audit(db, user, "login", "user", user.id)
    db.commit()
    return {"access": make_token(user.id, "access"), "refresh": make_token(user.id, "refresh"), "user": user_out(user)}


@router.post("/refresh")
def refresh(body: RefreshBody, db: Session = Depends(get_db)):
    try:
        uid = decode_token(body.refresh, "refresh")
    except jwt.PyJWTError:
        raise HTTPException(401, "invalid refresh token")
    user = db.get(User, uuid.UUID(uid))
    if not user or not user.active:
        raise HTTPException(401, "user disabled")
    return {"access": make_token(user.id, "access"), "refresh": make_token(user.id, "refresh")}


@router.get("/me")
def me(user: User = Depends(current_user)):
    return user_out(user)
