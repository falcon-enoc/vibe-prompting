from __future__ import annotations

import asyncio
import logging
import time
from uuid import uuid4

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
import numpy as np

from ..auth import _authenticate, log_request
from ..stt.parakeet_mlx import ParakeetMLXBackend

logger = logging.getLogger("vibe_prompt.transcribe_stream")

router = APIRouter()

# Safety cap so a forgotten-open connection can't hold the model lock forever.
MAX_SESSION_SECONDS = 600


@router.websocket("/transcribe/stream")
async def transcribe_stream(websocket: WebSocket) -> None:
    settings = websocket.app.state.settings
    backend = websocket.app.state.stt_backend

    if backend is None or not isinstance(backend, ParakeetMLXBackend):
        await websocket.accept()
        await websocket.close(code=1008, reason="streaming_unsupported")
        return

    try:
        api_key_id = await _authenticate(
            websocket.headers.get("x-api-key"),
            websocket.client.host if websocket.client else None,
            settings,
        )
    except HTTPException:
        await websocket.close(code=1008, reason="unauthorized")
        return

    await websocket.accept()

    session = None
    total_samples = 0
    start = time.monotonic()
    got_error = False

    try:
        session = await backend.open_stream()
        while True:
            if time.monotonic() - start > MAX_SESSION_SECONDS:
                await websocket.send_json({"type": "error", "detail": "session_timeout"})
                break

            message = await websocket.receive()
            if message["type"] == "websocket.disconnect":
                break
            if message.get("text") == "stop":
                break
            audio_bytes = message.get("bytes")
            if not audio_bytes:
                continue

            audio_f32 = np.frombuffer(audio_bytes, dtype="<i2").astype(np.float32) / 32768.0
            total_samples += len(audio_f32)
            stable_text, text = await session.add_chunk(audio_f32)
            await websocket.send_json({"type": "partial", "text": text, "stable_text": stable_text})
    except WebSocketDisconnect:
        pass
    except Exception as e:
        got_error = True
        logger.exception("Live transcription session error")
        try:
            await websocket.send_json({"type": "error", "detail": str(e)[:300]})
        except Exception:
            pass
    finally:
        final_text = ""
        processing_ms = (time.monotonic() - start) * 1000
        if session is not None:
            try:
                final_text = session.current_text
            except Exception:
                pass
            try:
                await session.close()
            finally:
                backend.release_stream()

        duration_ms = total_samples / 16000 * 1000
        if not got_error:
            try:
                await websocket.send_json({
                    "type": "final",
                    "text": final_text,
                    "duration_ms": duration_ms,
                    "processing_ms": processing_ms,
                })
            except Exception:
                pass

        asyncio.create_task(log_request(
            settings.API_KEY_DB,
            request_id=uuid4().hex,
            api_key_id=api_key_id,
            audio_duration_ms=duration_ms,
            processing_ms=processing_ms,
            status="error" if got_error else "success",
        ))

        try:
            await websocket.close()
        except Exception:
            pass
