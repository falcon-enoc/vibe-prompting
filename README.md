# Vibe Prompt

Dictado local para macOS con Apple Silicon. Transcribe voz a texto usando Parakeet TDT 0.6B v3 via MLX, sin enviar audio a la nube.

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

## Permisos macOS

- **Microfono**: obligatorio. macOS pedira permiso en el primer uso.
- **Accesibilidad**: necesario para auto-paste. Activar en Preferencias del Sistema > Privacidad y Seguridad > Accesibilidad.

## Modelo

Parakeet TDT 0.6B v3 -- 600M parametros, 25 idiomas europeos. Corre localmente en Apple Neural Engine via MLX.
