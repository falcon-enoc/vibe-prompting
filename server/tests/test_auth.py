from __future__ import annotations
import io
import math
import struct
import wave

import pytest


def _make_wav_bytes(num_frames: int = 8000, amplitude: int = 10000) -> bytes:
    """500ms 440Hz tone by default — long and loud enough to clear the
    server's minimum-duration/energy gate in routes/transcribe.py."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(16000)
        samples = [
            int(amplitude * math.sin(2 * math.pi * 440 * i / 16000))
            for i in range(num_frames)
        ]
        wf.writeframes(struct.pack(f"<{num_frames}h", *samples))
    return buf.getvalue()


@pytest.mark.anyio
async def test_no_api_key_returns_401(remote_client):
    """A non-localhost caller without an API key must be rejected."""
    wav_bytes = _make_wav_bytes()
    response = await remote_client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
    )
    assert response.status_code == 401


@pytest.mark.anyio
async def test_no_api_key_from_localhost_is_allowed(client):
    """Localhost callers are explicitly trusted without an API key
    (see vibe_prompt.auth._is_localhost) — pinning this down so a future
    change to that bypass is a deliberate, visible test update."""
    wav_bytes = _make_wav_bytes()
    response = await client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
    )
    assert response.status_code == 200


@pytest.mark.anyio
async def test_wrong_api_key_returns_401(client):
    wav_bytes = _make_wav_bytes()
    response = await client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
        headers={"X-API-Key": "totally-wrong-key"},
    )
    assert response.status_code == 401


@pytest.mark.anyio
async def test_correct_api_key_returns_200(client, test_api_key):
    wav_bytes = _make_wav_bytes()
    response = await client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
        headers={"X-API-Key": test_api_key},
    )
    assert response.status_code == 200
