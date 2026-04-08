import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from pathlib import Path
from .config import Settings, SUPPORTED_MODELS
from .stt import create_backend
from .model_manager import ModelManager
from .auth import init_db, ensure_dev_key, admin_router
from .routes.health import router as health_router
from .routes.transcribe import router as transcribe_router
from .routes.models import router as models_router
from .middleware import (
    RequestIDMiddleware,
    global_exception_handler,
    setup_rate_limiting,
    setup_cors,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("vibe_prompt")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = Settings()
    model_info = SUPPORTED_MODELS.get(settings.MODEL_ID, {})
    backend_type = model_info.get("backend", settings.MODEL_BACKEND)
    logger.info(f"Backend: {backend_type} | Model: {settings.MODEL_ID}")
    app.state.settings = settings
    app.state.model_manager = ModelManager(Path(settings.MODEL_STORAGE_PATH).expanduser())
    app.state.stt_backend = create_backend(backend_type, settings.MODEL_ID)
    await init_db(settings.API_KEY_DB)
    await ensure_dev_key(settings.API_KEY_DB)
    logger.info("Server ready.")
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="Vibe Prompt Server", version="0.1.0", lifespan=lifespan)

    # Middleware (order matters: first added = outermost)
    setup_cors(app)
    setup_rate_limiting(app, Settings())
    app.add_middleware(RequestIDMiddleware)
    app.add_exception_handler(Exception, global_exception_handler)

    # Routes
    app.include_router(health_router)
    app.include_router(transcribe_router)
    app.include_router(models_router)
    app.include_router(admin_router)
    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn
    settings = Settings()
    uvicorn.run(
        "vibe_prompt.main:app",
        host=settings.HOST,
        port=settings.PORT,
        workers=1,
        reload=False,
    )
