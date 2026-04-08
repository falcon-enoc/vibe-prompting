"""Placeholder for Parakeet TDT 0.6B v3 backend. Not yet implemented."""
from __future__ import annotations
import numpy as np
from .protocol import TranscribeResult


class ParakeetMLXBackend:
    """Parakeet TDT 0.6B v3 backend stub.

    To implement: install parakeet-mlx, load model, implement transcribe().
    Switch via MODEL_BACKEND=parakeet-0.6b in .env
    """

    def __init__(self, model_id: str = "nvidia/parakeet-tdt-0.6b-v2") -> None:
        raise NotImplementedError(
            "Parakeet backend not yet implemented. Set MODEL_BACKEND=whisper-base."
        )

    async def transcribe(
        self, audio: np.ndarray, language: str | None = None
    ) -> TranscribeResult:
        raise NotImplementedError

    async def health(self) -> dict:
        raise NotImplementedError
