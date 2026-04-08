from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Depends, Request

from ..auth import require_api_key
from ..models import ModelInfo, ModelsResponse

router = APIRouter()


def _list_downloaded_models() -> list[ModelInfo]:
    """Scan HuggingFace cache for downloaded whisper MLX models."""
    cache_dir = Path.home() / ".cache" / "huggingface" / "hub"
    models: list[ModelInfo] = []
    if not cache_dir.exists():
        return models

    for entry in sorted(cache_dir.iterdir()):
        if not entry.name.startswith("models--"):
            continue

        # Parse: models--org--name → org/name
        parts = entry.name.split("--", 2)
        if len(parts) < 3:
            continue

        model_id = f"{parts[1]}/{parts[2]}"

        # Only whisper MLX models
        name_lower = model_id.lower()
        if "whisper" not in name_lower or "mlx" not in name_lower:
            continue

        # Verify model has a snapshot (fully downloaded)
        snapshots = entry / "snapshots"
        if not snapshots.exists() or not any(snapshots.iterdir()):
            continue

        # Calculate size from blobs (actual files, not symlinks)
        blobs = entry / "blobs"
        if blobs.exists():
            size_bytes = sum(f.stat().st_size for f in blobs.iterdir() if f.is_file())
        else:
            size_bytes = 0

        # Display name: "whisper-base-mlx" → "Whisper Base"
        display = parts[2].replace("-mlx", "").replace("-", " ").title()

        models.append(ModelInfo(id=model_id, name=display, size_mb=round(size_bytes / (1024 * 1024))))

    return sorted(models, key=lambda m: m.size_mb)


@router.get("/models", response_model=ModelsResponse)
async def list_models(
    request: Request,
    _: str = Depends(require_api_key),
) -> ModelsResponse:
    models = _list_downloaded_models()
    current = request.app.state.settings.MODEL_ID
    return ModelsResponse(models=models, current=current)
