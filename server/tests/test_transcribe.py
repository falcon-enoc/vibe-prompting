from __future__ import annotations
import io
import math
import struct
import wave

import pytest


def _make_wav_bytes(num_frames: int = 8000, amplitude: int = 10000) -> bytes:
    """Build a minimal valid PCM WAV (mono, 16-bit, 16 kHz) in memory.

    `amplitude=0` produces pure silence; otherwise a 440Hz tone loud enough
    to clear the server's energy gate.
    """
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # int16
        wf.setframerate(16000)
        if amplitude:
            samples = [
                int(amplitude * math.sin(2 * math.pi * 440 * i / 16000))
                for i in range(num_frames)
            ]
            wf.writeframes(struct.pack(f"<{num_frames}h", *samples))
        else:
            wf.writeframes(b"\x00\x00" * num_frames)
    return buf.getvalue()


@pytest.mark.anyio
async def test_transcribe_valid_wav(client, test_api_key):
    wav_bytes = _make_wav_bytes(num_frames=8000, amplitude=10000)  # 500ms tone
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
async def test_transcribe_too_short(client, test_api_key):
    """Audio below the minimum duration is rejected before it can wake the model."""
    wav_bytes = _make_wav_bytes(num_frames=160, amplitude=10000)  # 10ms
    response = await client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
        headers={"X-API-Key": test_api_key},
    )
    assert response.status_code == 422


@pytest.mark.anyio
async def test_transcribe_silent(client, test_api_key):
    """Silent audio is rejected even when long enough, so it never reaches the model."""
    wav_bytes = _make_wav_bytes(num_frames=8000, amplitude=0)  # 500ms of silence
    response = await client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
        headers={"X-API-Key": test_api_key},
    )
    assert response.status_code == 422


@pytest.mark.anyio
async def test_transcribe_no_api_key(remote_client):
    """A non-localhost caller without an API key must be rejected."""
    wav_bytes = _make_wav_bytes(160)
    response = await remote_client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
    )
    assert response.status_code == 401
