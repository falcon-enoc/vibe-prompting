from __future__ import annotations
import hashlib
import tempfile
from pathlib import Path

import aiosqlite
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from vibe_prompt.main import create_app
from vibe_prompt.stt.protocol import TranscribeResult


# ---------------------------------------------------------------------------
# Mock STT backend
# ---------------------------------------------------------------------------

class MockSTTBackend:
    async def transcribe(self, audio, language=None, model=None) -> TranscribeResult:
        return TranscribeResult(
            text="hola mundo",
            language="es",
            duration_ms=1000.0,
            processing_ms=100.0,
            model="mock",
        )

    async def health(self) -> dict:
        return {"model_loaded": True, "model": "mock"}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def mock_backend():
    return MockSTTBackend()


@pytest.fixture
def test_api_key():
    return "test-key-12345"


@pytest_asyncio.fixture(scope="function")
async def client(mock_backend, test_api_key):
    app = create_app()

    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = str(Path(tmpdir) / "test_api_keys.db")

        # Pre-create the DB and insert test key
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
            await db.execute(
                """
                CREATE TABLE IF NOT EXISTS request_log (
                    id INTEGER PRIMARY KEY,
                    request_id TEXT NOT NULL,
                    timestamp TEXT NOT NULL,
                    api_key_id INTEGER,
                    audio_duration_ms REAL,
                    processing_ms REAL,
                    language_detected TEXT,
                    status TEXT NOT NULL,
                    error_detail TEXT
                )
                """
            )
            key_hash = hashlib.sha256(test_api_key.encode()).hexdigest()
            await db.execute(
                "INSERT INTO api_keys (key_hash, label, created_at, is_active) VALUES (?, ?, ?, 1)",
                (key_hash, "test", "2024-01-01T00:00:00+00:00"),
            )
            await db.commit()

        # Patch lifespan by manually setting app state before transport is used
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as ac:
            # Override state after app startup would normally run
            # We use a custom lifespan override via startup event patching
            app.state.stt_backend = mock_backend
            app.state.model_manager = type("MockModelManager", (), {
                "list_models": lambda self: [],
                "is_downloaded": lambda self, m: False,
            })()
            app.state.settings = type(
                "Settings",
                (),
                {"API_KEY_DB": db_path, "ADMIN_TOKEN": "test-admin-token", "MODEL_ID": "mock", "MAX_AUDIO_SIZE_MB": 25, "RATE_LIMIT_TRANSCRIBE": "30/minute", "RATE_LIMIT_ADMIN": "10/minute"},
            )()
            yield ac
