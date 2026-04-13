from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, Header, HTTPException, Request

from ..auth import require_api_key
from ..config import SUPPORTED_MODELS
from ..models import ModelInfo, ModelsResponse
from ..stt import create_backend

router = APIRouter()
logger = logging.getLogger("vibe_prompt")


@router.get("/models", response_model=ModelsResponse)
async def list_models(
    request: Request,
    _: int = Depends(require_api_key),
) -> ModelsResponse:
    current = request.app.state.settings.MODEL_ID
    model_manager = request.app.state.model_manager
    models = [
        ModelInfo(
            id=model_id,
            name=info["name"],
            backend=info["backend"],
            size_mb=info["size_mb"],
            downloaded=model_manager.is_downloaded(model_id) or model_id == current,
        )
        for model_id, info in SUPPORTED_MODELS.items()
    ]
    return ModelsResponse(models=models, current=current)


def _require_admin_token(
    request: Request,
    x_admin_token: str | None = Header(default=None),
) -> str | None:
    # Allow localhost without admin token
    client = request.client
    if client and client.host in ("127.0.0.1", "::1", "localhost"):
        return x_admin_token
    if x_admin_token != request.app.state.settings.ADMIN_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid admin token")
    return x_admin_token


@router.post("/models/switch")
async def switch_model(
    request: Request,
    model_id: str,
    _: str = Depends(_require_admin_token),
):
    if model_id not in SUPPORTED_MODELS:
        raise HTTPException(status_code=422, detail=f"Modelo no soportado: {model_id}")

    model_manager = request.app.state.model_manager
    if not model_manager.is_downloaded(model_id):
        raise HTTPException(status_code=404, detail="Modelo no está descargado en el servidor")

    model_info = SUPPORTED_MODELS[model_id]
    backend_type = model_info["backend"]
    local_path = str(model_manager.get_local_path(model_id))

    logger.info(f"Switching model to {model_id} (backend: {backend_type})")
    request.app.state.stt_backend = create_backend(backend_type, local_path)
    request.app.state.settings.MODEL_ID = model_id

    return {"status": "switched", "model_id": model_id}
