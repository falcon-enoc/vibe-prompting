from __future__ import annotations
import asyncio
import time
import numpy as np
from .protocol import TranscribeResult


class WhisperMLXBackend:
    def __init__(self, model_id: str = "mlx-community/whisper-base-mlx") -> None:
        import mlx_whisper
        self._mlx_whisper = mlx_whisper
        self._model_id = model_id
        self._lock = asyncio.Lock()
        # Warm-up: download and load model into Metal memory
        print(f"Loading model {model_id}...")
        mlx_whisper.transcribe(
            np.zeros(16000, dtype=np.float32),
            path_or_hf_repo=model_id,
        )
        print("Model ready.")

    def _transcribe_sync(self, audio: np.ndarray, language: str | None) -> dict:
        kwargs: dict = {"path_or_hf_repo": self._model_id}
        if language is not None:
            kwargs["language"] = language
        return self._mlx_whisper.transcribe(audio, **kwargs)

    async def transcribe(
        self, audio: np.ndarray, language: str | None = None
    ) -> TranscribeResult:
        duration_ms = len(audio) / 16000 * 1000
        async with self._lock:
            start = time.perf_counter()
            result = await asyncio.to_thread(self._transcribe_sync, audio, language)
            processing_ms = (time.perf_counter() - start) * 1000
        return TranscribeResult(
            text=result["text"].strip(),
            language=result.get("language"),
            duration_ms=duration_ms,
            processing_ms=processing_ms,
            model=self._model_id,
        )

    async def health(self) -> dict:
        return {"model_loaded": True, "model": self._model_id}
