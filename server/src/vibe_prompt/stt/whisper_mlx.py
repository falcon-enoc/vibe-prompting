from __future__ import annotations
import asyncio
import logging
import time
import numpy as np
from .protocol import TranscribeResult

logger = logging.getLogger("vibe_prompt.whisper")


class WhisperMLXBackend:
    def __init__(self, model_id: str = "mlx-community/whisper-base-mlx") -> None:
        import mlx_whisper
        self._mlx_whisper = mlx_whisper
        self._model_id = model_id
        self._lock = asyncio.Lock()
        self._loaded = False
        self.last_used = time.time()

    def _warmup(self) -> None:
        logger.info(f"Loading Whisper model from {self._model_id}")
        t0 = time.perf_counter()
        self._mlx_whisper.transcribe(
            np.zeros(16000, dtype=np.float32),
            path_or_hf_repo=self._model_id,
        )
        self._loaded = True
        self.last_used = time.time()
        logger.info(f"Whisper model ready in {(time.perf_counter() - t0):.1f}s")

    def is_loaded(self) -> bool:
        return self._loaded

    def unload(self) -> None:
        self._loaded = False
        logger.info("Whisper model unloaded from memory")

    def _transcribe_sync(self, audio: np.ndarray, language: str | None, model_id: str) -> dict:
        if not self._loaded:
            self._warmup()
        kwargs: dict = {"path_or_hf_repo": model_id, "task": "transcribe"}
        if language is not None:
            kwargs["language"] = language
        return self._mlx_whisper.transcribe(audio, **kwargs)

    async def transcribe(
        self, audio: np.ndarray, language: str | None = None, model: str | None = None
    ) -> TranscribeResult:
        used_model = model or self._model_id
        duration_ms = len(audio) / 16000 * 1000
        logger.debug(f"Transcribing {duration_ms:.0f}ms of audio")
        async with self._lock:
            start = time.perf_counter()
            result = await asyncio.to_thread(self._transcribe_sync, audio, language, used_model)
            processing_ms = (time.perf_counter() - start) * 1000
        self.last_used = time.time()
        text = result["text"].strip()
        rtf = processing_ms / duration_ms if duration_ms > 0 else 0
        logger.info(
            f"Transcribed {duration_ms:.0f}ms audio in {processing_ms:.0f}ms "
            f"(RTF {rtf:.2f}) | {len(text)} chars"
        )
        return TranscribeResult(
            text=text,
            language=result.get("language"),
            duration_ms=duration_ms,
            processing_ms=processing_ms,
            model=used_model,
        )

    async def health(self) -> dict:
        return {"model_loaded": self._loaded, "model": self._model_id}
