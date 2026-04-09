# Deploy del servidor VibePrompt

Guia para desplegar el servidor de transcripcion en una Mac remota (Apple Silicon requerido).

## Requisitos

- macOS 14+ (Sonoma)
- Apple Silicon (M1/M2/M3/M4) — MLX necesita Metal
- Python 3.12+
- ~500MB de disco para whisper-base, ~2.5GB para parakeet

## Modelos soportados

| Modelo | ID | Tamano | Idiomas | Velocidad |
|--------|----|--------|---------|-----------|
| Whisper Tiny | `mlx-community/whisper-tiny-mlx` | 39 MB | Multi | Muy rapido, menor precision |
| **Whisper Base** | `mlx-community/whisper-base-mlx` | 137 MB | Multi | Rapido, buena precision (default) |
| Parakeet TDT 0.6B | `mlx-community/parakeet-tdt-0.6b-v3` | 2.3 GB | Solo ingles | Mas lento, alta precision |

## Deploy rapido (automatico)

Desde tu Mac local con acceso SSH al servidor:

```bash
# 1. Definir el host del servidor
export MAC_MINI_HOST=usuario@ip-del-servidor

# 2. Provision inicial (solo la primera vez)
make deploy-install

# 3. Deploys subsiguientes (actualizar codigo)
make deploy-server
```

`deploy-install` ejecuta `deploy/setup-mac-mini.sh` que:
- Crea virtual environment
- Instala dependencias
- Descarga whisper-base-mlx
- Genera una API key
- Instala el servicio launchd (auto-inicio)

## Deploy manual (paso a paso)

### 1. Clonar y preparar

```bash
# En el servidor remoto
git clone <repo-url> ~/vibe-prompt
cd ~/vibe-prompt/server

# Crear venv e instalar
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

### 2. Configurar

```bash
cp ../.env.example .env
nano .env
```

Editar `.env`:

```bash
# Token de HuggingFace (necesario para descargar modelos)
HF_TOKEN=hf_tu_token_aqui

# Modelo inicial (whisper-base recomendado)
MODEL_BACKEND=whisper-base
MODEL_ID=mlx-community/whisper-base-mlx

# Seguridad — CAMBIAR estos valores
ADMIN_TOKEN=un-token-seguro-aqui

# Red
HOST=0.0.0.0
PORT=8420
```

### 3. Generar API key

```bash
make create-api-key
# Guarda la key que aparece — es para los clientes remotos
```

Nota: desde localhost no se necesita API key. Las keys son para clientes que se conectan desde otras maquinas.

### 4. Descargar modelo

El modelo se descarga automaticamente al primer request, o puedes forzarlo:

```bash
cd ~/vibe-prompt/server
source .venv/bin/activate
PYTHONPATH=src python3 -c "
import numpy as np
import mlx_whisper
mlx_whisper.transcribe(
    np.zeros(16000, dtype=np.float32),
    path_or_hf_repo='mlx-community/whisper-base-mlx',
)
print('Modelo descargado.')
"
```

### 5. Iniciar servidor

**Opcion A — Manual (para pruebas):**

```bash
make server-dev
```

**Opcion B — Servicio launchd (produccion):**

```bash
# Instalar el plist (reemplaza USER con tu usuario)
sed "s|/Users/USER|$HOME|g" deploy/vibe-prompt-server.plist > \
    ~/Library/LaunchAgents/com.vibeprompt.server.plist

# Iniciar
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.vibeprompt.server.plist
```

### 6. Verificar

```bash
curl http://localhost:8420/health | python3 -m json.tool
```

Respuesta esperada:

```json
{
    "status": "ok",
    "model": "mlx-community/whisper-base-mlx",
    "model_state": "loaded"
}
```

## Cambiar modelo en caliente

Desde localhost (sin admin token):

```bash
# Ver modelos disponibles
curl http://localhost:8420/models

# Cambiar a otro modelo
curl -X POST "http://localhost:8420/models/switch?model_id=mlx-community/whisper-tiny-mlx"
```

Desde remoto (con admin token):

```bash
curl -X POST "http://servidor:8420/models/switch?model_id=mlx-community/whisper-tiny-mlx" \
    -H "X-Admin-Token: tu-admin-token"
```

## Conectar el cliente

En la app VibePrompt > Preferencias > Servidores:

| Campo | Valor |
|-------|-------|
| Nombre | Mi servidor remoto |
| URL | `http://ip-del-servidor:8420` |
| API Key | La key generada en paso 3 |
| Admin Token | El ADMIN_TOKEN del .env (solo si quieres cambiar modelos) |

## Comandos utiles

```bash
# Ver logs del servidor
tail -f ~/Library/Logs/vibe-prompt/stderr.log

# Reiniciar servidor
launchctl kickstart -k gui/$(id -u)/com.vibeprompt.server

# Parar servidor
launchctl bootout gui/$(id -u)/com.vibeprompt.server

# Generar otra API key
cd ~/vibe-prompt && make create-api-key

# Estado del servicio
launchctl print gui/$(id -u)/com.vibeprompt.server
```

## Firewall / Red

Si el servidor debe ser accesible desde fuera de la red local:

- Abrir puerto 8420 en el firewall de macOS
- Configurar port forwarding en el router
- Considerar poner Nginx delante como reverse proxy con SSL (config en `deploy/nginx/`)
- **Nunca exponer el servidor sin API key a internet**

## Troubleshooting

| Problema | Solucion |
|----------|----------|
| `ModuleNotFoundError: mlx` | Apple Silicon requerido. MLX no funciona en Intel |
| Puerto 8420 ocupado | `lsof -i :8420` para ver que proceso lo usa |
| Modelo no carga | Verificar HF_TOKEN y espacio en disco |
| 401 desde cliente remoto | Verificar que el cliente tiene la API key correcta |
| Servidor no arranca tras reboot | Verificar que el plist esta en ~/Library/LaunchAgents/ |
