import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from .config import Settings
from .stt import create_backend
from .auth import init_db, ensure_dev_key, admin_router
from .routes.health import router as health_router
from .routes.transcribe import router as transcribe_router

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("vibe_prompt")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = Settings()
    logger.info(f"Backend: {settings.MODEL_BACKEND} | Model: {settings.MODEL_ID}")
    app.state.settings = settings
    app.state.stt_backend = create_backend(settings.MODEL_BACKEND, settings.MODEL_ID)
    await init_db(settings.API_KEY_DB)
    await ensure_dev_key(settings.API_KEY_DB)
    logger.info("Server ready.")
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="Vibe Prompt Server", version="0.1.0", lifespan=lifespan)
    app.include_router(health_router)
    app.include_router(transcribe_router)
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
