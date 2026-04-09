"""Parakeet TDT backend using parakeet-mlx on Apple Silicon."""
from __future__ import annotations
import asyncio, time
import numpy as np
import mlx.core as mx
from parakeet_mlx import from_pretrained
from parakeet_mlx.audio import get_logmel
from .protocol import TranscribeResult


class ParakeetMLXBackend:
    def __init__(self, model_path: str = "mlx-community/parakeet-tdt-0.6b-v3") -> None:
        self._model_path = model_path
        self._lock = asyncio.Lock()
        self._model = None
        self._loaded = False
        self.last_used = time.time()
        self._warmup()

    def _warmup(self) -> None:
        print(f"Loading model {self._model_path}...")
        self._model = from_pretrained(self._model_path)
        silence = mx.zeros((32000,), dtype=mx.float32)
        mel = get_logmel(silence, self._model.preprocessor_config)
        self._model.generate(mel)
        self._loaded = True
        self.last_used = time.time()
        print("Model ready.")

    def is_loaded(self) -> bool:
        return self._loaded

    def unload(self) -> None:
        self._model = None
        self._loaded = False

    def _transcribe_sync(self, audio: np.ndarray) -> str:
        if not self._loaded:
            self._warmup()
        audio_mx = mx.array(audio, dtype=mx.float32)
        mel = get_logmel(audio_mx, self._model.preprocessor_config)
        result = self._model.generate(mel)[0]
        return result.text.strip()

    async def transcribe(
        self, audio: np.ndarray, language: str | None = None, model: str | None = None
    ) -> TranscribeResult:
        duration_ms = len(audio) / 16000 * 1000
        async with self._lock:
            start = time.perf_counter()
            text = await asyncio.to_thread(self._transcribe_sync, audio)
            processing_ms = (time.perf_counter() - start) * 1000
        self.last_used = time.time()
        return TranscribeResult(
            text=text, language="en", duration_ms=duration_ms,
            processing_ms=processing_ms, model=self._model_path,
        )

    async def health(self) -> dict:
        return {"model_loaded": self._loaded, "model": self._model_path}
