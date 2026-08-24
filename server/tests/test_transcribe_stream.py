from __future__ import annotations
import hashlib
import tempfile
import time
from pathlib import Path

import aiosqlite
import pytest
from starlette.testclient import TestClient, WebSocketDisconnect

from vibe_prompt.main import create_app
from vibe_prompt.stt.parakeet_mlx import ParakeetMLXBackend

TEST_API_KEY = "test-key-12345"


# ---------------------------------------------------------------------------
# Fake Parakeet backend — real ParakeetMLXBackend (so open_stream/release_stream/
# the lock/StreamingSession are exercised for real), with a stubbed-out model so
# no MLX/HuggingFace weights are needed.
# ---------------------------------------------------------------------------

class _FakeResult:
    def __init__(self, text: str) -> None:
        self.text = text


class _FakeStreamingParakeet:
    def __init__(self, raise_on_add: bool = False) -> None:
        self._chunks = 0
        self._raise_on_add = raise_on_add

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> bool:
        return False

    def add_audio(self, audio_mx) -> None:
        if self._raise_on_add:
            raise RuntimeError("boom")
        self._chunks += 1

    @property
    def result(self) -> _FakeResult:
        return _FakeResult(f"chunk-{self._chunks}" if self._chunks else "")


class _FakeModel:
    def __init__(self, raise_on_add: bool = False) -> None:
        self._raise_on_add = raise_on_add

    def transcribe_stream(self, context_size=(256, 256), **kwargs) -> _FakeStreamingParakeet:
        return _FakeStreamingParakeet(raise_on_add=self._raise_on_add)


class FakeParakeetBackend(ParakeetMLXBackend):
    def __init__(self, raise_on_add: bool = False) -> None:
        super().__init__(model_path="fake-parakeet")
        self._raise_on_add = raise_on_add

    def _warmup(self) -> None:
        self._model = _FakeModel(raise_on_add=self._raise_on_add)
        self._loaded = True
        self.last_used = time.time()


class NonStreamingBackend:
    """Stand-in for a Whisper backend — must be rejected by the streaming route."""
    last_used = time.time()

    async def transcribe(self, audio, language=None, model=None):
        raise NotImplementedError

    async def health(self) -> dict:
        return {"model_loaded": True, "model": "mock-whisper"}

    def is_loaded(self) -> bool:
        return True

    def unload(self) -> None:
        pass


# ---------------------------------------------------------------------------
# App/client setup
# ---------------------------------------------------------------------------

def _build_test_client(backend, client_addr: tuple[str, int]) -> TestClient:
    app = create_app()

    tmpdir = tempfile.mkdtemp()
    db_path = str(Path(tmpdir) / "test_api_keys.db")

    import asyncio

    async def _seed_db():
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
            key_hash = hashlib.sha256(TEST_API_KEY.encode()).hexdigest()
            await db.execute(
                "INSERT INTO api_keys (key_hash, label, created_at, is_active) VALUES (?, ?, ?, 1)",
                (key_hash, "test", "2024-01-01T00:00:00+00:00"),
            )
            await db.commit()

    asyncio.run(_seed_db())

    app.state.stt_backend = backend
    app.state.model_manager = type("MockModelManager", (), {
        "list_models": lambda self: [],
        "is_downloaded": lambda self, m: False,
    })()
    app.state.settings = type(
        "Settings",
        (),
        {
            "API_KEY_DB": db_path,
            "ADMIN_TOKEN": "test-admin-token",
            "MODEL_ID": "mock",
            "MAX_AUDIO_SIZE_MB": 25,
            "RATE_LIMIT_TRANSCRIBE": "30/minute",
            "RATE_LIMIT_ADMIN": "10/minute",
            "IDLE_UNLOAD_MINUTES": 10,
        },
    )()

    return TestClient(app, client=client_addr)


def _pcm_chunk(num_samples: int = 800) -> bytes:
    """~50ms of mono int16 16kHz silence — content doesn't matter, only shape."""
    return b"\x00\x00" * num_samples


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_stream_rejected_when_no_backend():
    client = _build_test_client(None, ("127.0.0.1", 123))
    with client.websocket_connect("/transcribe/stream") as ws:
        with pytest.raises(WebSocketDisconnect) as exc_info:
            ws.receive_text()
        assert exc_info.value.code == 1008


def test_stream_rejected_when_backend_not_parakeet():
    client = _build_test_client(NonStreamingBackend(), ("127.0.0.1", 123))
    with client.websocket_connect("/transcribe/stream") as ws:
        with pytest.raises(WebSocketDisconnect) as exc_info:
            ws.receive_text()
        assert exc_info.value.code == 1008


def test_stream_rejected_without_api_key_from_remote_host():
    backend = FakeParakeetBackend()
    client = _build_test_client(backend, ("203.0.113.5", 54321))
    # Unauthorized sessions are closed before accept(), so the handshake
    # itself fails rather than a later receive().
    with pytest.raises(WebSocketDisconnect) as exc_info:
        with client.websocket_connect("/transcribe/stream"):
            pass
    assert exc_info.value.code == 1008


def test_stream_partial_and_final():
    backend = FakeParakeetBackend()
    client = _build_test_client(backend, ("127.0.0.1", 123))
    with client.websocket_connect("/transcribe/stream") as ws:
        ws.send_bytes(_pcm_chunk())
        msg1 = ws.receive_json()
        assert msg1["type"] == "partial"
        assert msg1["text"] == "chunk-1"

        ws.send_bytes(_pcm_chunk())
        msg2 = ws.receive_json()
        assert msg2["type"] == "partial"
        assert msg2["text"] == "chunk-2"

        ws.send_text("stop")
        final = ws.receive_json()
        assert final["type"] == "final"
        assert final["text"] == "chunk-2"
        assert final["duration_ms"] > 0

    assert not backend._lock.locked()


def test_stream_zero_chunks_before_stop():
    backend = FakeParakeetBackend()
    client = _build_test_client(backend, ("127.0.0.1", 123))
    with client.websocket_connect("/transcribe/stream") as ws:
        ws.send_text("stop")
        final = ws.receive_json()
        assert final["type"] == "final"
        assert final["text"] == ""

    assert not backend._lock.locked()


def test_stream_error_during_chunk_releases_lock():
    backend = FakeParakeetBackend(raise_on_add=True)
    client = _build_test_client(backend, ("127.0.0.1", 123))
    with client.websocket_connect("/transcribe/stream") as ws:
        ws.send_bytes(_pcm_chunk())
        msg = ws.receive_json()
        assert msg["type"] == "error"

    assert not backend._lock.locked()
