from __future__ import annotations

from fastapi import APIRouter, Depends, Request

from ..auth import require_api_key
from ..config import SUPPORTED_MODELS
from ..models import ModelInfo, ModelsResponse

router = APIRouter()


@router.get("/models", response_model=ModelsResponse)
async def list_models(
    request: Request,
    _: int = Depends(require_api_key),
) -> ModelsResponse:
    models = [
        ModelInfo(
            id=model_id,
            name=info["name"],
            backend=info["backend"],
            size_mb=info["size_mb"],
            downloaded=request.app.state.model_manager.is_downloaded(model_id),
        )
        for model_id, info in SUPPORTED_MODELS.items()
    ]
    current = request.app.state.settings.MODEL_ID
    return ModelsResponse(models=models, current=current)
