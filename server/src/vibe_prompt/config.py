from pydantic_settings import BaseSettings, SettingsConfigDict

SUPPORTED_MODELS: dict[str, dict] = {
    "mlx-community/whisper-tiny-mlx": {"name": "Whisper Tiny", "backend": "whisper", "size_mb": 39},
    "mlx-community/whisper-base-mlx": {"name": "Whisper Base", "backend": "whisper", "size_mb": 137},
    "mlx-community/parakeet-tdt-0.6b-v3": {"name": "Parakeet TDT 0.6B", "backend": "parakeet", "size_mb": 2300},
}


class Settings(BaseSettings):
    MODEL_BACKEND: str = "whisper-base"
    MODEL_ID: str = "mlx-community/whisper-base-mlx"
    MODEL_STORAGE_PATH: str = "~/Library/Application Support/VibePrompt/models"
    LANGUAGE: str | None = None
    HOST: str = "127.0.0.1"
    PORT: int = 8420
    ADMIN_TOKEN: str = "change-me"
    API_KEY_DB: str = "data/api_keys.db"
    RATE_LIMIT_TRANSCRIBE: str = "30/minute"
    RATE_LIMIT_ADMIN: str = "10/minute"
    MAX_AUDIO_SIZE_MB: int = 25
    IDLE_UNLOAD_MINUTES: int = 10
    HF_TOKEN: str | None = None

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")
