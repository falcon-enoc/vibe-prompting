from pydantic import BaseModel


class TranscribeResponse(BaseModel):
    text: str
    language: str | None = None
    duration_ms: float
    processing_ms: float
    model: str


class HealthResponse(BaseModel):
    status: str
    model_loaded: bool
    model: str
    idle_seconds: int = 0
    idle_unload_minutes: int = 0


class ModelInfo(BaseModel):
    id: str
    name: str
    backend: str
    size_mb: int
    downloaded: bool


class ModelsResponse(BaseModel):
    models: list[ModelInfo]
    current: str
