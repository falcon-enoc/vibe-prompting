"""Download the configured model to the local ModelManager storage path."""
import asyncio
from pathlib import Path

from vibe_prompt.config import Settings
from vibe_prompt.model_manager import ModelManager


async def main() -> None:
    s = Settings()
    mm = ModelManager(Path(s.MODEL_STORAGE_PATH).expanduser())

    if mm.is_downloaded(s.MODEL_ID):
        print(f"Modelo ya descargado: {mm.get_local_path(s.MODEL_ID)}")
        return

    print(f"Descargando {s.MODEL_ID}...")
    if s.HF_TOKEN:
        print("HF_TOKEN detectado — usando autenticación.")
    path = await mm.download(s.MODEL_ID, hf_token=s.HF_TOKEN)
    print(f"Modelo listo en: {path}")


asyncio.run(main())
