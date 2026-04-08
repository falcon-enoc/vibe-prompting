from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    MODEL_BACKEND: str = "whisper-base"
    MODEL_ID: str = "mlx-community/whisper-base-mlx"
    LANGUAGE: str | None = None
    HOST: str = "0.0.0.0"
    PORT: int = 8420
    ADMIN_TOKEN: str = "change-me"
    API_KEY_DB: str = "data/api_keys.db"

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")
