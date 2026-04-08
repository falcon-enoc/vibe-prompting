from __future__ import annotations

import asyncio
import re
import shutil
import struct
import subprocess

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
import numpy as np

from ..auth import require_api_key, log_request
from ..models import TranscribeResponse

router = APIRouter()

TARGET_SAMPLE_RATE = 16000

_LANG_RE = re.compile(r"^[a-z]{2}$")


def _parse_wav(data: bytes) -> tuple[np.ndarray, int]:
    offset = 12
    fmt_info: dict = {}
    audio_data = b""

    while offset + 8 <= len(data):
        chunk_id = data[offset:offset + 4]
        chunk_size = struct.unpack_from("<I", data, offset + 4)[0]
        if chunk_id == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", data, offset + 8)
            fmt_info = {"channels": fmt[1], "sample_rate": fmt[2], "bits_per_sample": fmt[5]}
        elif chunk_id == b"data":
            audio_data = data[offset + 8: offset + 8 + chunk_size]
        offset += 8 + chunk_size

    if not fmt_info or not audio_data:
        raise ValueError("Invalid WAV: missing fmt or data chunk")

    bits = fmt_info["bits_per_sample"]
    dtype = np.int16 if bits == 16 else (np.int32 if bits == 32 else np.float32)
    raw = np.frombuffer(audio_data, dtype=dtype)

    channels = fmt_info["channels"]
    if channels > 1:
        raw = raw.reshape(-1, channels).mean(axis=1)

    if dtype == np.int16:
        audio_f32 = raw.astype(np.float32) / 32768.0
    elif dtype == np.int32:
        audio_f32 = raw.astype(np.float32) / 2147483648.0
    else:
        audio_f32 = raw.astype(np.float32)

    return audio_f32, fmt_info["sample_rate"]


def _resample(audio: np.ndarray, orig_sr: int, target_sr: int) -> np.ndarray:
    if orig_sr == target_sr:
        return audio
    target_len = int(len(audio) / orig_sr * target_sr)
    return np.interp(
        np.linspace(0, len(audio) - 1, target_len),
        np.arange(len(audio)),
        audio,
    ).astype(np.float32)


def _decode_with_ffmpeg(audio_bytes: bytes) -> np.ndarray:
    if not shutil.which("ffmpeg"):
        raise RuntimeError("ffmpeg not found. Install with: brew install ffmpeg")

    cmd = [
        "ffmpeg",
        "-hide_banner", "-loglevel", "error",
        "-i", "pipe:0",
        "-ac", "1",
        "-ar", str(TARGET_SAMPLE_RATE),
        "-f", "f32le",
        "pipe:1",
    ]
    result = subprocess.run(cmd, input=audio_bytes, capture_output=True)
    if result.returncode != 0:
        raise ValueError(f"ffmpeg error: {result.stderr.decode()[:200]}")

    return np.frombuffer(result.stdout, dtype=np.float32)


async def _to_float32_16k(audio_bytes: bytes) -> np.ndarray:
    is_wav = audio_bytes[:4] == b"RIFF" and audio_bytes[8:12] == b"WAVE"

    if is_wav:
        audio_f32, sample_rate = _parse_wav(audio_bytes)
        return _resample(audio_f32, sample_rate, TARGET_SAMPLE_RATE)

    return await asyncio.to_thread(_decode_with_ffmpeg, audio_bytes)


# Audio is processed in memory only — never written to disk.
@router.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(
    request: Request,
    audio: UploadFile = File(...),
    language: str | None = Form(None),
    api_key_id: int = Depends(require_api_key),
) -> TranscribeResponse:
    settings = request.app.state.settings
    audio_bytes = await audio.read()

    max_bytes = settings.MAX_AUDIO_SIZE_MB * 1024 * 1024
    if len(audio_bytes) > max_bytes:
        raise HTTPException(status_code=413, detail=f"Audio excede {settings.MAX_AUDIO_SIZE_MB}MB")

    if len(audio_bytes) < 12:
        raise HTTPException(status_code=422, detail="Audio demasiado corto")

    if language and not _LANG_RE.match(language):
        raise HTTPException(status_code=422, detail="Código de idioma inválido (esperado: ISO 639-1, ej: es, en)")

    try:
        audio_f32 = await _to_float32_16k(audio_bytes)
    except (ValueError, RuntimeError) as e:
        raise HTTPException(status_code=422, detail=str(e))

    if len(audio_f32) == 0:
        raise HTTPException(status_code=422, detail="Audio vacío después de decodificar")

    request_id = getattr(request.state, "request_id", "unknown")

    try:
        result = await request.app.state.stt_backend.transcribe(audio_f32, language)
        asyncio.create_task(log_request(
            settings.API_KEY_DB,
            request_id=request_id,
            api_key_id=api_key_id,
            audio_duration_ms=result.duration_ms,
            processing_ms=result.processing_ms,
            language_detected=result.language,
            status="success",
        ))
        return TranscribeResponse(
            text=result.text,
            language=result.language,
            duration_ms=result.duration_ms,
            processing_ms=result.processing_ms,
            model=result.model,
        )
    except Exception as e:
        asyncio.create_task(log_request(
            settings.API_KEY_DB,
            request_id=request_id,
            api_key_id=api_key_id,
            status="error",
            error_detail=str(e)[:500],
        ))
        raise
