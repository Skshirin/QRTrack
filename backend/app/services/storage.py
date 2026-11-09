import hashlib

import boto3
from botocore.client import Config
from botocore.exceptions import ClientError

from ..config import settings


def _client(endpoint: str):
    return boto3.client(
        "s3", endpoint_url=endpoint or None, aws_access_key_id=settings.s3_access_key,
        aws_secret_access_key=settings.s3_secret_key, region_name=settings.s3_region,
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


internal = _client(settings.s3_endpoint)
public = _client(settings.s3_public_endpoint)  # presigned URLs must be signed for the host the phone uses


def ensure_bucket():
    try:
        internal.head_bucket(Bucket=settings.s3_bucket)
    except ClientError:
        internal.create_bucket(Bucket=settings.s3_bucket)


def presign_put(key: str, content_type: str = "image/jpeg", expires: int = 600) -> str:
    return public.generate_presigned_url(
        "put_object", Params={"Bucket": settings.s3_bucket, "Key": key, "ContentType": content_type}, ExpiresIn=expires)


def presign_get(key: str, expires: int = 3600) -> str:
    return public.generate_presigned_url("get_object", Params={"Bucket": settings.s3_bucket, "Key": key}, ExpiresIn=expires)


def check_object(key: str, sha256: str):
    """Returns (size, hash_ok). Raises ClientError if the object is missing."""
    head = internal.head_object(Bucket=settings.s3_bucket, Key=key)
    size = head["ContentLength"]
    if size > settings.max_photo_bytes:
        internal.delete_object(Bucket=settings.s3_bucket, Key=key)
        return size, False
    body = internal.get_object(Bucket=settings.s3_bucket, Key=key)["Body"].read()
    return size, hashlib.sha256(body).hexdigest() == sha256
