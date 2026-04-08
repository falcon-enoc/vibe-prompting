from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, Request

from ..auth import require_api_key
from ..config import SUPPORTED_MODELS
from ..models import ModelInfo, ModelsResponse

router = APIRouter()


@router.get("/models", response_model=ModelsResponse)
async def list_models(
    request: Request,
    _: int = Depends(require_api_key),
) -> ModelsResponse:
    model_manager = request.app.state.model_manager
    models = [
        ModelInfo(
            id=m["id"],
            name=m["name"],
            backend=m["backend"],
            size_mb=m["size_mb"],
            downloaded=m["downloaded"],
        )
        for m in model_manager.list_models()
    ]
    current = request.app.state.settings.MODEL_ID
    return ModelsResponse(models=models, current=current)


def _require_admin_token(
    request: Request,
    x_admin_token: str = Header(...),
) -> str:
    if x_admin_token != request.app.state.settings.ADMIN_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid admin token")
    return x_admin_token


@router.post("/models/download")
async def download_model(
    request: Request,
    model_id: str,
    _: str = Depends(_require_admin_token),
    hf_token: str | None = Header(None, alias="X-HF-Token"),
):
    if model_id not in SUPPORTED_MODELS:
        raise HTTPException(status_code=422, detail=f"Modelo no soportado: {model_id}")

    model_manager = request.app.state.model_manager
    if model_manager.is_downloaded(model_id):
        return {"status": "already_downloaded", "model_id": model_id}

    token = hf_token or request.app.state.settings.HF_TOKEN
    path = await model_manager.download(model_id, hf_token=token)
    return {"status": "downloaded", "model_id": model_id, "path": str(path)}


@router.delete("/models/{model_id:path}")
async def delete_model(
    request: Request,
    model_id: str,
    _: str = Depends(_require_admin_token),
):
    if model_id not in SUPPORTED_MODELS:
        raise HTTPException(status_code=422, detail=f"Modelo no soportado: {model_id}")

    if model_id == request.app.state.settings.MODEL_ID:
        raise HTTPException(status_code=409, detail="No se puede eliminar el modelo activo")

    model_manager = request.app.state.model_manager
    if not model_manager.is_downloaded(model_id):
        raise HTTPException(status_code=404, detail="Modelo no está descargado")

    await model_manager.delete(model_id)
    return {"status": "deleted", "model_id": model_id}
