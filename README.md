# Vibe Prompt

Dictado local para macOS con Apple Silicon. Transcribe voz a texto usando Parakeet TDT 0.6B v3 via MLX, sin enviar audio a la nube.

## Índice

- [Requisitos](#requisitos)
- [Setup](#setup)
- [Uso](#uso)
- [Indicador de grabación](#indicador-de-grabacion)
- [Servidor local](#servidor-local)
  - [Instalación del servidor local (desde la app)](#instalación-del-servidor-local-desde-la-app)
  - [Grabaciones muy cortas o silenciosas](#grabaciones-muy-cortas-o-silenciosas)
- [Permisos macOS](#permisos-macos)
- [Modelo](#modelo)
- [Licencia](#licencia)

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

## Indicador de grabación

Mientras grabas aparece un **HUD flotante** (píldora estilo *liquid glass*) centrado
arriba, bajo la barra de menú, por encima de todas las ventanas — incluso apps fullscreen:

- **Grabando**: onda que reacciona al nivel real del micrófono.
- **Transcribiendo**: spinner con "Transcribiendo…".
- **Listo / Error**: check verde o aviso amarillo por un instante, y se desvanece.

No intercepta clicks ni roba el foco. Se puede desactivar en
*Preferencias › General › Comportamiento › "Indicador flotante al grabar"*.

## Servidor local

La transcripción la hace un servidor (FastAPI + MLX) al que la app le envía el audio.
Puede ser un servidor **remoto** o uno **local** en tu propio Mac. Cuando el servidor
activo es local (`127.0.0.1`), la app **levanta y detiene el servidor por sí sola**:

- Arranca automáticamente al abrir la app o al seleccionar el servidor local.
- Botón **Iniciar/Detener** en el menú de la barra y en *Preferencias › Servidores*.
- Se detiene al salir de la app o al cambiar a un servidor remoto.
- Picker para elegir el modelo local (Parakeet o Whisper) y cambiarlo en caliente.

### Instalación del servidor local (desde la app)

La primera vez, instalá el entorno del servidor con un botón — **no hace falta clonar el
repo ni instalar Python a mano**:

1. *Preferencias › Servidores*, con el servidor local seleccionado → **Instalar servidor local**.
2. La app usa `uv` (empaquetado en la app) para descargar un Python 3.12 propio, crear un
   entorno en `~/Library/Application Support/VibePrompt/server` e instalar las dependencias
   (~300–500 MB, una sola vez).
3. Al terminar, el servidor arranca solo. Descargá un modelo en *Preferencias › Modelos*
   (Parakeet ~2.5 GB) y ya podés dictar.

Requisitos: **Apple Silicon** y conexión a internet en la primera instalación. Todo el
entorno vive en `~/Library/Application Support/VibePrompt/` (borrable sin tocar nada más).
Si algo falla, usá **Reinstalar / reparar servidor** en la misma pantalla.

> **Desarrollo:** si tenés un checkout del repo con `make server-install` (crea el `.venv`),
> la app lo autodetecta y tiene prioridad sobre el entorno instalado. También podés fijar la
> ruta manualmente en *Preferencias › Servidores › Ruta del proyecto (dev)*.

### Grabaciones muy cortas o silenciosas

El modelo se carga en memoria bajo demanda (en la primera transcripción) y se descarga solo
tras un rato sin uso. Para que un clic accidental del atajo no dispare esa carga innecesaria,
una grabación de menos de ~400ms o sin voz audible (silencio/ruido de tecla) se descarta antes
de enviarse — no se transcribe ni se muestra error, solo un sonido corto y vuelta a idle.

## Permisos macOS

- **Microfono**: obligatorio. macOS pedira permiso en el primer uso.
- **Accesibilidad**: necesario para auto-paste. Activar en Preferencias del Sistema > Privacidad y Seguridad > Accesibilidad.

## Modelo

Parakeet TDT 0.6B v3 -- 600M parametros, 25 idiomas europeos. Corre localmente en Apple Neural Engine via MLX.

## Licencia

Distribuido bajo licencia MIT. Ver [LICENSE](LICENSE).
