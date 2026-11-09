from alembic import context
from sqlalchemy import create_engine

from app import models  # noqa: F401
from app.config import settings
from app.db import Base


def include_object(obj, name, type_, reflected, compare_to):
    if type_ == "table" and name == "spatial_ref_sys":
        return False
    return True


engine = create_engine(settings.database_url)
with engine.connect() as conn:
    context.configure(connection=conn, target_metadata=Base.metadata, include_object=include_object)
    with context.begin_transaction():
        context.run_migrations()
