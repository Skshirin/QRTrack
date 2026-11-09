import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from .config import settings
from .db import Base, engine
from .routers import auth, ops, photos, registry, sync
from .services import storage

log = logging.getLogger("kanha")


@asynccontextmanager
async def lifespan(app: FastAPI):
    with engine.begin() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
    if settings.auto_create_tables:
        from . import models  # noqa: F401
        Base.metadata.create_all(engine)
    try:
        storage.ensure_bucket()
    except Exception:  # noqa: BLE001
        log.exception("object storage not reachable yet")
    yield


app = FastAPI(title="Kanha QR Monitoring API", version="1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins.split(","), allow_methods=["*"], allow_headers=["*"],
                   expose_headers=["X-Tag-Count", "Content-Disposition"])
for r in (auth.router, sync.router, photos.router, registry.router, ops.router):
    app.include_router(r, prefix="/api/v1")


@app.get("/health")
def health():
    return {"ok": True}
