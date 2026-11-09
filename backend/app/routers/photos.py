import uuid
from datetime import datetime, timezone

from botocore.exceptions import ClientError
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

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
