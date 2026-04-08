from .protocol import STTBackend, TranscribeResult
from .whisper_mlx import WhisperMLXBackend
from .parakeet_mlx import ParakeetMLXBackend

__all__ = ["STTBackend", "TranscribeResult", "WhisperMLXBackend", "ParakeetMLXBackend", "create_backend"]


def create_backend(model_backend: str, model_id: str) -> STTBackend:
    match model_backend:
        case "whisper-base":
            return WhisperMLXBackend(model_id=model_id)
        case "parakeet-0.6b":
            return ParakeetMLXBackend(model_id=model_id)
        case _:
            raise ValueError(
                f"Unknown backend: {model_backend!r}. "
                "Supported: 'whisper-base', 'parakeet-0.6b'."
            )
