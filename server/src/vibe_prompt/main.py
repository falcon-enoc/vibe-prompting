import asyncio
import logging
import time
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
from .routes.logs import router as logs_router
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
    app.state.settings = settings

    model_manager = ModelManager(Path(settings.MODEL_STORAGE_PATH).expanduser())
    app.state.model_manager = model_manager

    if model_manager.is_downloaded(settings.MODEL_ID):
        local_path = str(model_manager.get_local_path(settings.MODEL_ID))
        logger.info(f"Local model found: {settings.MODEL_ID} ({backend_type})")
        app.state.stt_backend = create_backend(backend_type, local_path)
    else:
        logger.info(
            f"No local model found for '{settings.MODEL_ID}'. "
            "Server running without a model — use the /models endpoint to download one."
        )
        app.state.stt_backend = None

    await init_db(settings.API_KEY_DB)
    await ensure_dev_key(settings.API_KEY_DB)
    logger.info("Server ready.")

    # Background idle-unload checker
    async def _idle_checker():
        if settings.IDLE_UNLOAD_MINUTES <= 0:
            return
        timeout = settings.IDLE_UNLOAD_MINUTES * 60
        while True:
            await asyncio.sleep(60)
            backend = app.state.stt_backend
            if backend is not None and backend.is_loaded() and (time.time() - backend.last_used) > timeout:
                logger.info("Idle timeout — unloading model from memory")
                backend.unload()

    idle_task = asyncio.create_task(_idle_checker())
    try:
        yield
    finally:
        idle_task.cancel()


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
    app.include_router(logs_router)
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
