"""Parakeet TDT backend using parakeet-mlx on Apple Silicon."""
from __future__ import annotations
import asyncio
import gc
import logging
import time
import numpy as np
import mlx.core as mx
from parakeet_mlx import from_pretrained
from parakeet_mlx.audio import get_logmel
from .protocol import TranscribeResult

logger = logging.getLogger("vibe_prompt.parakeet")


class ParakeetMLXBackend:
    def __init__(self, model_path: str = "mlx-community/parakeet-tdt-0.6b-v3") -> None:
        self._model_path = model_path
        self._lock = asyncio.Lock()
        self._model = None
        self._loaded = False
        self.last_used = time.time()

    def _warmup(self) -> None:
        logger.info(f"Loading Parakeet model from {self._model_path}")
        t0 = time.perf_counter()
        self._model = from_pretrained(self._model_path)
        silence = mx.zeros((32000,), dtype=mx.float32)
        mel = get_logmel(silence, self._model.preprocessor_config)
        self._model.generate(mel)
        self._loaded = True
        self.last_used = time.time()
        logger.info(f"Parakeet model ready in {(time.perf_counter() - t0):.1f}s")

    def is_loaded(self) -> bool:
        return self._loaded

    def unload(self) -> None:
        self._model = None
        self._loaded = False
        # MLX keeps freed Metal buffers in a cache; without this the GPU memory
        # stays resident (GBs) even after the model is gone.
        gc.collect()
        mx.clear_cache()
        logger.info("Parakeet model unloaded from memory")

    def trim_cache(self) -> None:
        """Release MLX's cached Metal buffers while the model stays loaded.
        Skipped if a transcription/stream holds the lock."""
        if self._lock.locked():
            return
        cache_mb = mx.get_cache_memory() / 2**20
        mx.clear_cache()
        logger.info(f"MLX cache trimmed ({cache_mb:.0f} MB released)")

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
        logger.debug(f"Transcribing {duration_ms:.0f}ms of audio")
        async with self._lock:
            start = time.perf_counter()
            text = await asyncio.to_thread(self._transcribe_sync, audio)
            processing_ms = (time.perf_counter() - start) * 1000
        self.last_used = time.time()
        rtf = processing_ms / duration_ms if duration_ms > 0 else 0
        logger.info(
            f"Transcribed {duration_ms:.0f}ms audio in {processing_ms:.0f}ms "
            f"(RTF {rtf:.2f}) | {len(text)} chars"
        )
        return TranscribeResult(
            text=text, language=language or "auto", duration_ms=duration_ms,
            processing_ms=processing_ms, model=self._model_path,
        )

    async def health(self) -> dict:
        return {"model_loaded": self._loaded, "model": self._model_path}

    async def open_stream(self) -> "ParakeetMLXBackend.StreamingSession":
        """Start a live-transcription session. Acquires the backend lock for the
        whole session lifetime (released via release_stream(), not here) so a
        concurrent batch /transcribe call can't interleave with this model
        instance. Caller must always pair this with release_stream() in a
        finally block, even on error."""
        await self._lock.acquire()
        try:
            if not self._loaded:
                await asyncio.to_thread(self._warmup)
            stream = self._model.transcribe_stream(context_size=(256, 256))
            await asyncio.to_thread(stream.__enter__)
            self.last_used = time.time()
            return ParakeetMLXBackend.StreamingSession(self, stream)
        except Exception:
            self._lock.release()
            raise

    def release_stream(self) -> None:
        """Release the lock acquired by open_stream(). Must be called exactly
        once per open_stream(), after the session's close() has run."""
        self._lock.release()

    class StreamingSession:
        """One live-transcription session bound to a locked ParakeetMLXBackend.
        Created only via ParakeetMLXBackend.open_stream()."""

        def __init__(self, backend: "ParakeetMLXBackend", stream) -> None:
            self._backend = backend
            self._stream = stream

        async def add_chunk(self, pcm_f32: np.ndarray) -> str:
            """Feed one chunk of mono float32 16kHz PCM, return the current
            best merged transcript (finalized + in-progress draft text)."""
            audio_mx = mx.array(pcm_f32, dtype=mx.float32)
            text = await asyncio.to_thread(self._add_chunk_sync, audio_mx)
            self._backend.last_used = time.time()
            return text

        def _add_chunk_sync(self, audio_mx) -> str:
            self._stream.add_audio(audio_mx)
            return self._stream.result.text

        @property
        def current_text(self) -> str:
            return self._stream.result.text

        async def close(self) -> None:
            await asyncio.to_thread(self._stream.__exit__, None, None, None)
