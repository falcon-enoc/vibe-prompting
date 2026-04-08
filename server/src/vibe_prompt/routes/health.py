from fastapi import APIRouter, Request
from ..models import HealthResponse

router = APIRouter()


@router.get("/health", response_model=HealthResponse)
async def health(request: Request) -> HealthResponse:
    info = await request.app.state.stt_backend.health()
    return HealthResponse(status="ok", **info)
