from .protocol import STTBackend, TranscribeResult
from .whisper_mlx import WhisperMLXBackend
from .parakeet_mlx import ParakeetMLXBackend

__all__ = ["STTBackend", "TranscribeResult", "WhisperMLXBackend", "ParakeetMLXBackend", "create_backend"]


def create_backend(backend_type: str, model_path: str) -> STTBackend:
    match backend_type:
        case "whisper":
            return WhisperMLXBackend(model_id=model_path)
        case "parakeet":
            return ParakeetMLXBackend(model_path=model_path)
        case _:
            raise ValueError(
                f"Unknown backend: {backend_type!r}. "
                "Supported: 'whisper', 'parakeet'."
            )
