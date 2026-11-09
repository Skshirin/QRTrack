import hashlib
import uuid
from datetime import datetime, timezone

from botocore.exceptions import ClientError
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.responses import RedirectResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..deps import current_user
from ..models import Photo, User
from ..services import storage

router = APIRouter(prefix="/photos", tags=["photos"])


class UploadBody(BaseModel):
    photo_id: uuid.UUID


@router.post("/upload-url")
def upload_url(body: UploadBody, user: User = Depends(current_user), db: Session = Depends(get_db)):
    photo = db.get(Photo, body.photo_id)  # the photo record must have been synced first
    if not photo or photo.uploaded_by != user.id:
        raise HTTPException(404, "photo record not found - sync records before photos")
    return {"url": storage.presign_put(photo.storage_key), "key": photo.storage_key,
            "headers": {"Content-Type": "image/jpeg"}, "expires_in": 600}


@router.post("/{photo_id}/upload")
async def upload_direct(photo_id: uuid.UUID, request: Request, user: User = Depends(current_user), db: Session = Depends(get_db)):
    """Direct photo upload to backend, eliminating S3/MinIO hostname or network routing issues for mobile devices."""
    photo = db.get(Photo, photo_id)
    if not photo or photo.uploaded_by != user.id:
        raise HTTPException(404, "photo record not found - sync records before photos")
    body = await request.body()
    if len(body) > settings.max_photo_bytes:
        raise HTTPException(422, "photo too large")
    h = hashlib.sha256(body).hexdigest()
    if photo.sha256 and photo.sha256 != h:
        raise HTTPException(422, f"photo hash mismatch: client={photo.sha256} server={h}")
    storage.put_object(photo.storage_key, body)
    photo.size_bytes = len(body)
    photo.confirmed_at = datetime.now(timezone.utc)
    db.commit()
    return {"ok": True, "size": len(body)}


@router.post("/{photo_id}/confirm")
def confirm(photo_id: uuid.UUID, user: User = Depends(current_user), db: Session = Depends(get_db)):
    photo = db.get(Photo, photo_id)
    if not photo or photo.uploaded_by != user.id:
        raise HTTPException(404, "photo not found")
    try:
        size, ok = storage.check_object(photo.storage_key, photo.sha256)
    except ClientError:
        raise HTTPException(409, "file not in storage yet")
    if size > 10**9 or not ok:
        raise HTTPException(422, "photo too large or hash mismatch")
    photo.size_bytes, photo.confirmed_at = size, datetime.now(timezone.utc)
    db.commit()
    return {"ok": True, "size": size}


@router.get("/{photo_id}")
def get_photo(photo_id: uuid.UUID, user: User = Depends(current_user), db: Session = Depends(get_db)):
    photo = db.get(Photo, photo_id)
    if not photo or not photo.confirmed_at:
        raise HTTPException(404, "photo not found or unconfirmed")
    return RedirectResponse(storage.presign_get(photo.storage_key))

