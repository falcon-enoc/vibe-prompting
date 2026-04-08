from __future__ import annotations
from dataclasses import dataclass
from typing import Protocol
import numpy as np


@dataclass
class TranscribeResult:
    text: str
    language: str | None
    duration_ms: float
    processing_ms: float
    model: str


class STTBackend(Protocol):
    last_used: float

    async def transcribe(
        self, audio: np.ndarray, language: str | None = None, model: str | None = None
    ) -> TranscribeResult: ...

    async def health(self) -> dict: ...

    def is_loaded(self) -> bool: ...

    def unload(self) -> None: ...
