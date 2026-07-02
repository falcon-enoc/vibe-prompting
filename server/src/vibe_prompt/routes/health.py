import time
from fastapi import APIRouter, Request
from ..models import HealthResponse

router = APIRouter()


def _active_memory_mb() -> float | None:
    """RAM (unificada) que MLX tiene activa — proxy del modelo cargado."""
    try:
        import mlx.core as mx

        return round(mx.get_active_memory() / 1e6, 1)
    except Exception:
        return None


@router.get("/health", response_model=HealthResponse)
async def health(request: Request) -> HealthResponse:
    backend = request.app.state.stt_backend
    settings = request.app.state.settings
    if backend is None:
        return HealthResponse(
            status="ok",
            model_loaded=False,
            model=None,
            idle_seconds=0,
            idle_unload_minutes=settings.IDLE_UNLOAD_MINUTES,
        )
    info = await backend.health()
    memory_mb = _active_memory_mb() if info.get("model_loaded") else None
    return HealthResponse(
        status="ok",
        idle_seconds=int(time.time() - backend.last_used),
        idle_unload_minutes=settings.IDLE_UNLOAD_MINUTES,
        memory_mb=memory_mb,
        **info,
    )
