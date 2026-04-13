from __future__ import annotations
import io
import wave

import pytest


def _make_wav_bytes(num_frames: int = 160) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(16000)
        wf.writeframes(b"\x00\x00" * num_frames)
    return buf.getvalue()


@pytest.mark.anyio
async def test_no_api_key_returns_401(client):
    wav_bytes = _make_wav_bytes()
    response = await client.post(
        "/transcribe",
        files={"audio": ("audio.wav", wav_bytes, "audio/wav")},
    )
    assert response.status_code == 401


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
