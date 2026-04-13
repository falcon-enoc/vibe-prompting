import time
from fastapi import APIRouter, Request
from ..models import HealthResponse

router = APIRouter()


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
    return HealthResponse(
        status="ok",
        idle_seconds=int(time.time() - backend.last_used),
        idle_unload_minutes=settings.IDLE_UNLOAD_MINUTES,
        **info,
    )
