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

# Buscar Python 3.12 o 3.13 (MLX no soporta 3.14+)
PYTHON_BIN=""
for candidate in python3.12 python3.13; do
    if command -v "$candidate" &>/dev/null; then
        PYTHON_BIN="$candidate"
        break
    fi
done

# Fallback a python3 si es version compatible
if [ -z "$PYTHON_BIN" ]; then
    if command -v python3 &>/dev/null; then
        PY_MINOR=$(python3 -c 'import sys; print(sys.version_info.minor)')
        if [ "$PY_MINOR" -ge 12 ] && [ "$PY_MINOR" -le 13 ]; then
            PYTHON_BIN="python3"
        else
            echo -e "${RED}Python 3.12 o 3.13 requerido (encontrado 3.$PY_MINOR).${NC}"
            echo "  Instala con: brew install python@3.12"
            exit 1
        fi
    else
        echo -e "${RED}Python 3 no encontrado. Instala con: brew install python@3.12${NC}"
        exit 1
    fi
fi

PYTHON_VERSION=$($PYTHON_BIN -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "Usando: $PYTHON_BIN (Python $PYTHON_VERSION)"

# 2. Crear directorios
echo -e "${YELLOW}Creando directorios...${NC}"
mkdir -p "$INSTALL_DIR/server/data"
mkdir -p "$LOG_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

# 3. Crear virtual environment (recrear si la version de Python no coincide)
RECREATE_VENV=false
if [ -d "$VENV_DIR" ]; then
    VENV_PY_VERSION=$("$VENV_DIR/bin/python3" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    if [ "$VENV_PY_VERSION" != "$PYTHON_VERSION" ]; then
        echo -e "${YELLOW}Venv existente usa Python $VENV_PY_VERSION, se necesita $PYTHON_VERSION. Recreando...${NC}"
        rm -rf "$VENV_DIR"
        RECREATE_VENV=true
    fi
else
    RECREATE_VENV=true
fi

if [ "$RECREATE_VENV" = true ]; then
    echo -e "${YELLOW}Creando virtual environment con Python $PYTHON_VERSION...${NC}"
    $PYTHON_BIN -m venv "$VENV_DIR"
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
from huggingface_hub import snapshot_download
print('Descargando modelo parakeet-tdt-0.6b-v3 (~2.3 GB)...')
snapshot_download('mlx-community/parakeet-tdt-0.6b-v3')
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
