from __future__ import annotations
import hashlib
import secrets
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated

import aiosqlite
from fastapi import APIRouter, Depends, Header, HTTPException, Request

from .config import Settings


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _hash_key(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# DB init / seed
# ---------------------------------------------------------------------------

async def init_db(db_path: str) -> None:
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            """
            CREATE TABLE IF NOT EXISTS api_keys (
                id         INTEGER PRIMARY KEY,
                key_hash   TEXT UNIQUE NOT NULL,
                label      TEXT,
                created_at TEXT,
                last_used  TEXT,
                is_active  INTEGER DEFAULT 1
            )
            """
        )
        await db.commit()


async def ensure_dev_key(db_path: str) -> str | None:
    async with aiosqlite.connect(db_path) as db:
        async with db.execute("SELECT COUNT(*) FROM api_keys") as cursor:
            row = await cursor.fetchone()
            count = row[0] if row else 0

    if count == 0:
        key = await create_api_key(db_path, label="dev")
        print("\n" + "=" * 60)
        print("  DEV API KEY (shown only once):")
        print(f"  {key}")
        print("=" * 60 + "\n")
        return key
    return None


async def create_api_key(db_path: str, label: str = "") -> str:
    key = secrets.token_urlsafe(32)
    key_hash = _hash_key(key)
    now = _now_iso()
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            "INSERT INTO api_keys (key_hash, label, created_at, is_active) VALUES (?, ?, ?, 1)",
            (key_hash, label, now),
        )
        await db.commit()
    return key


# ---------------------------------------------------------------------------
# FastAPI dependencies
# ---------------------------------------------------------------------------

def get_settings(request: Request) -> Settings:
    return request.app.state.settings


async def require_api_key(
    x_api_key: Annotated[str | None, Header(alias="X-API-Key")] = None,
    request: Request = None,
) -> str:
    if x_api_key is None:
        raise HTTPException(status_code=401, detail="Missing X-API-Key header")

    key_hash = _hash_key(x_api_key)
    settings: Settings = request.app.state.settings
    db_path = settings.API_KEY_DB

    async with aiosqlite.connect(db_path) as db:
        async with db.execute(
            "SELECT id, is_active FROM api_keys WHERE key_hash = ?",
            (key_hash,),
        ) as cursor:
            row = await cursor.fetchone()

        if row is None or row[1] != 1:
            raise HTTPException(status_code=401, detail="Invalid or inactive API key")

        await db.execute(
            "UPDATE api_keys SET last_used = ? WHERE id = ?",
            (_now_iso(), row[0]),
        )
        await db.commit()

    return x_api_key


# ---------------------------------------------------------------------------
# Admin router
# ---------------------------------------------------------------------------

admin_router = APIRouter(prefix="/admin", tags=["admin"])


@admin_router.post("/keys")
async def create_key(
    label: str = "",
    x_admin_token: Annotated[str | None, Header(alias="X-Admin-Token")] = None,
    settings: Settings = Depends(get_settings),
) -> dict:
    if x_admin_token != settings.ADMIN_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid admin token")
    key = await create_api_key(settings.API_KEY_DB, label=label)
    return {"key": key, "label": label}
