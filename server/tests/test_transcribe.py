from __future__ import annotations
import io
import struct
import wave

import pytest


def _make_wav_bytes(num_frames: int = 160) -> bytes:
    """Build a minimal valid PCM WAV (mono, 16-bit, 16 kHz) in memory."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # int16
        wf.setframerate(16000)
        wf.writeframes(b"\x00\x00" * num_frames)
    return buf.getvalue()


@pytest.mark.anyio
async def test_transcribe_valid_wav(client, test_api_key):
    wav_bytes = _make_wav_bytes(160)
    response = await client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
        headers={"X-API-Key": test_api_key},
    )
    assert response.status_code == 200
    data = response.json()
    assert "text" in data
    assert data["text"] == "hola mundo"


@pytest.mark.anyio
async def test_transcribe_no_api_key(remote_client):
    """A non-localhost caller without an API key must be rejected."""
    wav_bytes = _make_wav_bytes(160)
    response = await remote_client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
    )
    assert response.status_code == 401
