# Vibe Prompt - Comandos y API

## Servidor (Mac Mini)

### Gestionar el servicio

```bash
# Ver logs en tiempo real
tail -f ~/Library/Logs/vibe-prompt/stderr.log

# Reiniciar servidor
launchctl kickstart -k gui/$(id -u)/com.vibeprompt.server

# Parar servidor
launchctl bootout gui/$(id -u)/com.vibeprompt.server

# Iniciar servidor (si esta parado)
launchctl load ~/Library/LaunchAgents/com.vibeprompt.server.plist

# Health check
curl http://localhost:8420/health
```

### API Keys

```bash
# Crear API key (desde el Mac Mini, no necesita admin token)
make create-api-key

# Crear API key con label (via HTTP, desde localhost)
curl -X POST "http://localhost:8420/admin/keys?label=nombre-persona"
```

### Estadisticas de uso

```bash
# Ultimos 7 dias (default)
curl http://localhost:8420/admin/usage

# Ultimos 30 dias
curl "http://localhost:8420/admin/usage?days=30"
```

### Modelos

```bash
# Ver modelos disponibles y cual esta activo
curl http://localhost:8420/models

# Cambiar modelo (desde localhost, no necesita admin token)
curl -X POST "http://localhost:8420/models/switch?model_id=mlx-community/whisper-base-mlx"
```

### Actualizar servidor

```bash
cd ~/apps/vibe-prompting
git pull
launchctl kickstart -k gui/$(id -u)/com.vibeprompt.server
```

---

## Acceso remoto (via https://stt.example.com)

### Health check

```bash
curl https://stt.example.com/health
```

### Transcribir audio

```bash
# Transcribir un archivo de audio
curl -X POST https://stt.example.com/transcribe \
  -H "X-API-Key: TU_API_KEY" \
  -F "audio=@archivo.wav"

# Transcribir especificando idioma
curl -X POST https://stt.example.com/transcribe \
  -H "X-API-Key: TU_API_KEY" \
  -F "audio=@archivo.wav" \
  -F "language=es"
```

Formatos soportados: WAV, MP3, M4A, OGG, y cualquier formato compatible con ffmpeg.

### Administracion remota

Requiere el header `X-Admin-Token` configurado en el `.env` del servidor.

```bash
# Crear API key
curl -X POST "https://stt.example.com/admin/keys?label=nombre-persona" \
  -H "X-Admin-Token: TU_ADMIN_TOKEN"

# Ver estadisticas de uso
curl https://stt.example.com/admin/usage \
  -H "X-Admin-Token: TU_ADMIN_TOKEN"

# Ver modelos
curl https://stt.example.com/models \
  -H "X-API-Key: TU_API_KEY"

# Cambiar modelo
curl -X POST "https://stt.example.com/models/switch?model_id=mlx-community/whisper-base-mlx" \
  -H "X-Admin-Token: TU_ADMIN_TOKEN"
```

---

## Desarrollo (maquina local)

```bash
# Servidor en modo desarrollo (auto-reload)
make dev

# Correr tests
make test

# Lint
make lint

# Compilar cliente macOS (.dmg)
make client-dmg

# Abrir proyecto Xcode del cliente
make client-open
```

### Deploy al Mac Mini

```bash
# Provision inicial (primera vez)
make deploy-install MAC_MINI_HOST=user@192.168.1.180

# Actualizar servidor existente
make deploy-server MAC_MINI_HOST=user@192.168.1.180
```

### Tunnel Cloudflare

```bash
# Setup inicial del tunnel (interactivo)
make tunnel-setup

# Levantar / parar / logs del tunnel
make tunnel-up
make tunnel-down
make tunnel-logs
```

---

## Referencia rapida de headers

| Header | Donde se usa | Descripcion |
|--------|-------------|-------------|
| `X-API-Key` | `/transcribe`, `/models` | API key del usuario |
| `X-Admin-Token` | `/admin/*`, `/models/switch` | Token de administracion |

Desde localhost (127.0.0.1) ambos headers son opcionales.

## Rate limits

| Endpoint | Limite |
|----------|--------|
| `/transcribe` | 30 requests/minuto por API key |
| `/admin/*` | 10 requests/minuto |

## Respuesta de /transcribe

```json
{
  "text": "texto transcrito",
  "language": "es",
  "duration_ms": 3200,
  "processing_ms": 450,
  "model": "mlx-community/parakeet-tdt-0.6b-v3"
}
```
