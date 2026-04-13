#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${GREEN}=== Vibe Prompt — Cloudflare Tunnel Setup ===${NC}"
echo ""

# 1. Verificar Docker
if ! command -v docker &>/dev/null; then
    echo -e "${RED}Docker no encontrado. Instala Docker primero.${NC}"
    echo "  brew install --cask docker   (macOS)"
    echo "  curl -fsSL https://get.docker.com | sh   (Linux)"
    exit 1
fi

if ! docker info &>/dev/null 2>&1; then
    echo -e "${RED}Docker no esta corriendo. Inicia Docker primero.${NC}"
    exit 1
fi

echo -e "${GREEN}Docker OK${NC}"

# 2. Verificar que el servidor vibe-prompt esta corriendo
if curl -sf http://localhost:8420/health > /dev/null 2>&1; then
    echo -e "${GREEN}Servidor vibe-prompt OK (puerto 8420)${NC}"
else
    echo -e "${RED}El servidor vibe-prompt no responde en localhost:8420${NC}"
    echo "  Asegurate de que el servidor esta corriendo antes de levantar el tunnel."
    exit 1
fi

# 3. Crear .env si no existe
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo ""
    echo -e "${YELLOW}No se encontro .env — necesitas crear un tunnel en Cloudflare.${NC}"
    echo ""
    echo -e "${CYAN}Pasos:${NC}"
    echo "  1. Ve a https://one.dash.cloudflare.com → Networks → Tunnels"
    echo "  2. Crea un nuevo tunnel (tipo Cloudflared)"
    echo "  3. Dale un nombre (ej: vibe-prompt)"
    echo "  4. Copia el token que te da Cloudflare"
    echo "  5. En la config del tunnel, agrega un Public Hostname:"
    echo "     - Subdomain: stt (o el que quieras)"
    echo "     - Domain: tu-dominio.com"
    echo "     - Service: http://host.docker.internal:8420"
    echo ""
    read -rp "Pega tu TUNNEL_TOKEN aqui: " TOKEN

    if [ -z "$TOKEN" ]; then
        echo -e "${RED}Token vacio. Abortando.${NC}"
        exit 1
    fi

    echo "TUNNEL_TOKEN=$TOKEN" > "$SCRIPT_DIR/.env"
    echo -e "${GREEN}.env creado${NC}"
else
    echo -e "${GREEN}.env encontrado${NC}"
fi

# 4. Levantar el tunnel
echo ""
echo -e "${YELLOW}Levantando tunnel...${NC}"
cd "$SCRIPT_DIR"
docker compose up -d

# 5. Verificar
sleep 3
if docker compose ps --format '{{.State}}' | grep -q running; then
    echo ""
    echo -e "${GREEN}=== Tunnel activo ===${NC}"
    echo ""
    echo "El servidor ahora es accesible desde internet via tu dominio Cloudflare."
    echo ""
    echo "Comandos utiles:"
    echo "  Ver logs:    cd $SCRIPT_DIR && docker compose logs -f"
    echo "  Parar:       cd $SCRIPT_DIR && docker compose down"
    echo "  Reiniciar:   cd $SCRIPT_DIR && docker compose restart"
    echo "  Estado:      cd $SCRIPT_DIR && docker compose ps"
else
    echo -e "${RED}El tunnel no inicio correctamente. Revisa los logs:${NC}"
    echo "  cd $SCRIPT_DIR && docker compose logs"
fi
