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


class ModelInfo(BaseModel):
    id: str
    name: str
    size_mb: int


class ModelsResponse(BaseModel):
    models: list[ModelInfo]
    current: str
