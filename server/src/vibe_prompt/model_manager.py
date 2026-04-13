"""Manage downloading, listing, and deleting MLX models."""

import asyncio
import shutil
from pathlib import Path

from huggingface_hub import snapshot_download

from .config import SUPPORTED_MODELS


class ModelManager:
    def __init__(self, storage_path: Path):
        self.storage_path = storage_path.expanduser()
        self.storage_path.mkdir(parents=True, exist_ok=True)

    def _model_dir(self, model_id: str) -> Path:
        """Convert 'mlx-community/whisper-base-mlx' → storage_path / 'mlx-community--whisper-base-mlx'."""
        return self.storage_path / model_id.replace("/", "--")

    def list_models(self) -> list[dict]:
        """Return all supported models with 'id' and 'downloaded' fields."""
        return [
            {"id": model_id, **info, "downloaded": self.is_downloaded(model_id)}
            for model_id, info in SUPPORTED_MODELS.items()
        ]

    def is_downloaded(self, model_id: str) -> bool:
        """Check if the model directory exists and has files."""
        d = self._model_dir(model_id)
        return d.is_dir() and any(d.iterdir())

    def get_local_path(self, model_id: str) -> Path:
        """Return path if downloaded, raise ValueError if not."""
        if not self.is_downloaded(model_id):
            raise ValueError(f"Model '{model_id}' is not downloaded")
        return self._model_dir(model_id)

    async def download(self, model_id: str, hf_token: str | None = None) -> Path:
        """Download a model from HuggingFace Hub."""
        if model_id not in SUPPORTED_MODELS:
            raise ValueError(f"Model '{model_id}' is not supported")

        local_dir = self._model_dir(model_id)
        await asyncio.to_thread(
            snapshot_download,
            repo_id=model_id,
            local_dir=str(local_dir),
            token=hf_token,
        )
        return local_dir

    async def delete(self, model_id: str) -> None:
        """Remove a downloaded model directory."""
        if not self.is_downloaded(model_id):
            raise ValueError(f"Model '{model_id}' is not downloaded")
        await asyncio.to_thread(shutil.rmtree, self._model_dir(model_id))
