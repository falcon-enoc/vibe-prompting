# Vibe Prompt

Dictado local para macOS con Apple Silicon. Transcribe voz a texto usando Parakeet TDT 0.6B v3 via MLX, sin enviar audio a la nube.

## Índice

- [Requisitos](#requisitos)
- [Setup](#setup)
- [Uso](#uso)
- [Servidor local](#servidor-local)
- [Permisos macOS](#permisos-macos)
- [Modelo](#modelo)

## Requisitos

- Apple Silicon Mac (M1 o superior)
- macOS 13+
- Python 3.10+

## Setup

```bash
pip install -r requirements.txt
python dictate.py
```

Nota: el primer arranque descarga el modelo (~2.5 GB).

## Uso

1. Mantener presionado **Alt derecho** (push-to-talk)
2. Hablar
3. Soltar la tecla

El texto transcrito se pega automaticamente donde estes escribiendo y se copia al clipboard.

## Servidor local

La transcripción la hace un servidor (FastAPI + MLX) al que la app le envía el audio.
Puede ser un servidor **remoto** o uno **local** en tu propio Mac. Cuando el servidor
activo es local (`127.0.0.1`), la app **levanta y detiene el servidor por sí sola**:

- Arranca automáticamente al abrir la app o al seleccionar el servidor local.
- Botón **Iniciar/Detener** en el menú de la barra y en *Preferencias › Servidores*.
- Se detiene al salir de la app o al cambiar a un servidor remoto.
- Picker para elegir el modelo local (Parakeet o Whisper) y cambiarlo en caliente.

Requisito: tener el entorno del servidor instalado en el repo (`make server-install`,
crea el `.venv`) y el modelo descargado. La app detecta la ruta del proyecto
automáticamente; si no, se configura en *Preferencias › Servidores › Ruta del proyecto*.
Los modelos se guardan en `~/Library/Application Support/VibePrompt/models`.

## Permisos macOS

- **Microfono**: obligatorio. macOS pedira permiso en el primer uso.
- **Accesibilidad**: necesario para auto-paste. Activar en Preferencias del Sistema > Privacidad y Seguridad > Accesibilidad.

## Modelo

Parakeet TDT 0.6B v3 -- 600M parametros, 25 idiomas europeos. Corre localmente en Apple Neural Engine via MLX.
