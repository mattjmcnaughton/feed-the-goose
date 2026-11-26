"""A database for one test run, created by the real migrations and dropped after."""

import asyncio
import os
import subprocess
import sys
import uuid
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import create_async_engine

BACKEND = Path(__file__).resolve().parents[2]


def create(base_url: str) -> str:
    """Create an empty database next to `base_url`'s, migrate it to head, and
    return its URL."""
    url = make_url(base_url).set(database=f"ftg_test_{uuid.uuid4().hex[:12]}")
    asyncio.run(_admin(base_url, f'CREATE DATABASE "{url.database}"'))
    rendered = url.render_as_string(hide_password=False)
    try:
        subprocess.run(
            [sys.executable, "-m", "alembic", "upgrade", "head"],
            cwd=BACKEND,
            env={**os.environ, "DATABASE_URL": rendered},
            check=True,
            capture_output=True,
        )
    except BaseException:
        drop(base_url, rendered)
        raise
    return rendered


def drop(base_url: str, url: str) -> None:
    name = make_url(url).database
    asyncio.run(_admin(base_url, f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))


async def _admin(base_url: str, statement: str) -> None:
    admin = make_url(base_url).set(database="postgres")
    engine = create_async_engine(admin, isolation_level="AUTOCOMMIT")
    try:
        async with engine.connect() as connection:
            await connection.execute(text(statement))
    finally:
        await engine.dispose()
