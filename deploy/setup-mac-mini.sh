#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Vibe Prompt Server Setup ===${NC}"

INSTALL_DIR="$HOME/vibe-prompt"
VENV_DIR="$INSTALL_DIR/.venv"
LOG_DIR="$HOME/Library/Logs/vibe-prompt"
PLIST_SRC="$INSTALL_DIR/deploy/vibe-prompt-server.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.vibeprompt.server.plist"

# 1. Verificar prerequisitos
echo -e "${YELLOW}Verificando prerequisitos...${NC}"

if ! command -v python3 &>/dev/null; then
    echo -e "${RED}Python 3 no encontrado. Instala con: brew install python@3.12${NC}"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "Python version: $PYTHON_VERSION"

if [[ "$PYTHON_VERSION" < "3.12" ]]; then
    echo -e "${YELLOW}Advertencia: se recomienda Python 3.12+${NC}"
fi

# 2. Crear directorios
echo -e "${YELLOW}Creando directorios...${NC}"
mkdir -p "$INSTALL_DIR/server/data"
mkdir -p "$LOG_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

# 3. Crear virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Creando virtual environment...${NC}"
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

# 4. Instalar servidor
echo -e "${YELLOW}Instalando dependencias del servidor...${NC}"
cd "$INSTALL_DIR/server"
pip install --upgrade pip
pip install -e ".[dev]"

# 5. Crear .env si no existe
if [ ! -f "$INSTALL_DIR/server/.env" ]; then
    echo -e "${YELLOW}Creando .env desde plantilla...${NC}"
    cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/server/.env"
    echo -e "${RED}IMPORTANTE: Edita $INSTALL_DIR/server/.env con tus valores reales${NC}"
fi

# 6. Descargar modelo (warm-up)
echo -e "${YELLOW}Descargando y preparando modelo STT (puede tardar varios minutos)...${NC}"
cd "$INSTALL_DIR/server"
PYTHONPATH=src python3 -c "
import numpy as np
import mlx_whisper
print('Descargando modelo whisper-base-mlx...')
mlx_whisper.transcribe(
    np.zeros(16000, dtype=np.float32),
    path_or_hf_repo='mlx-community/whisper-base-mlx',
)
print('Modelo listo.')
"

# 7. Generar API key inicial
echo -e "${YELLOW}Generando API key...${NC}"
cd "$INSTALL_DIR/server"
PYTHONPATH=src python3 -c "
import asyncio
from vibe_prompt.auth import init_db, create_api_key
from vibe_prompt.config import Settings
async def main():
    s = Settings()
    await init_db(s.API_KEY_DB)
    key = await create_api_key(s.API_KEY_DB, 'setup')
    print('')
    print('='*50)
    print(f'Tu API Key: {key}')
    print('Guarda esta clave — no se mostrará de nuevo.')
    print('='*50)
    print('')
asyncio.run(main())
"

# 8. Instalar launchd plist
echo -e "${YELLOW}Instalando servicio launchd...${NC}"

# Reemplazar placeholder USER con el usuario actual
sed "s|/Users/USER|$HOME|g" "$PLIST_SRC" > "$PLIST_DST"

# Descargar si ya estaba cargado
launchctl bootout "gui/$(id -u)/com.vibeprompt.server" 2>/dev/null || true

# Cargar el servicio
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"

# 9. Esperar y verificar
echo -e "${YELLOW}Esperando que el servidor inicie...${NC}"
sleep 5

if curl -sf http://localhost:8420/health > /dev/null 2>&1; then
    echo -e "${GREEN}Servidor corriendo correctamente.${NC}"
    curl -s http://localhost:8420/health | python3 -m json.tool
else
    echo -e "${RED}El servidor puede no haber iniciado. Revisa los logs:${NC}"
    echo "  tail -f $LOG_DIR/stderr.log"
fi

echo ""
echo -e "${GREEN}=== Setup completado ===${NC}"
echo ""
echo "Comandos útiles:"
echo "  Ver logs:      tail -f $LOG_DIR/stderr.log"
echo "  Reiniciar:     launchctl kickstart -k gui/$(id -u)/com.vibeprompt.server"
echo "  Parar:         launchctl bootout gui/$(id -u)/com.vibeprompt.server"
echo "  Health check:  curl http://localhost:8420/health"
echo "  Nueva API key: cd $INSTALL_DIR && make create-api-key"
