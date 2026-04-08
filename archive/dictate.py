"""
Dictado push-to-talk para macOS con Apple Silicon.
Modelo Whisper base corriendo local via MLX.

Uso: python dictate.py
Hotkey: Manten Cmd derecho para grabar, suelta para transcribir y pegar.
Ctrl+C para salir.
"""

import sys
import time
import threading
import subprocess

from dotenv import load_dotenv
load_dotenv()

import numpy as np
import sounddevice as sd
from pynput import keyboard


# --- Configuracion de audio ---
SAMPLE_RATE = 16000
CHANNELS = 1
DTYPE = np.int16
MIN_DURATION = 0.3  # segundos minimos para procesar

# --- Modelo ---
MODEL_ID = "mlx-community/whisper-base-mlx"
LANGUAGE = None  # None = auto-detectar, "es" = forzar español, "en" = forzar inglés


class Dictator:
    def __init__(self):
        self.model = None
        self.recording = False
        self.audio_buffer = []
        self.record_start = 0.0
        self.lock = threading.Lock()
        self.stream = None

    def load_model(self):
        print("Cargando Whisper base (MLX)...")
        import mlx_whisper
        # Warm-up: descarga el modelo y lo deja en memoria
        mlx_whisper.transcribe(
            np.zeros(SAMPLE_RATE, dtype=np.float32),
            path_or_hf_repo=MODEL_ID,
        )
        self.model = mlx_whisper
        print("Modelo cargado. Manten Cmd derecho para dictar.")

    def _audio_callback(self, indata, frames, time_info, status):
        if status:
            print(f"Audio status: {status}")
        if self.recording:
            self.audio_buffer.append(indata.copy())

    def start_recording(self):
        if self.recording:
            return
        self.audio_buffer = []
        self.recording = True
        self.record_start = time.time()
        self.stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype=DTYPE,
            callback=self._audio_callback,
        )
        self.stream.start()
        print("Grabando...")

    def stop_recording_and_transcribe(self):
        if not self.recording:
            return
        self.recording = False
        if self.stream is not None:
            self.stream.stop()
            self.stream.close()
            self.stream = None

        duration = time.time() - self.record_start
        if duration < MIN_DURATION:
            print("Grabacion muy corta, ignorada.")
            return

        if not self.audio_buffer:
            print("Sin audio capturado.")
            return

        audio_data = np.concatenate(self.audio_buffer, axis=0)
        self._transcribe(audio_data)

    def _transcribe(self, audio_data):
        print("Transcribiendo...")
        try:
            # int16 → float32 normalizado [-1, 1], mono 1D
            audio_f32 = audio_data.squeeze().astype(np.float32) / 32768.0
            result = self.model.transcribe(
                audio_f32,
                path_or_hf_repo=MODEL_ID,
                language=LANGUAGE,
            )
            text = result["text"].strip()

            if not text:
                print("No se detecto texto.")
                return

            print(f"Texto: {text}")
            self._paste(text)

        except Exception as e:
            print(f"Error: {e}")

    def _paste(self, text):
        try:
            proc = subprocess.Popen(
                ["pbcopy"], stdin=subprocess.PIPE, text=True
            )
            proc.communicate(input=text)

            subprocess.run(
                [
                    "osascript",
                    "-e",
                    'tell application "System Events" to keystroke "v" using command down',
                ],
                check=True,
                capture_output=True,
            )
        except Exception as e:
            print(f"Error al pegar: {e}")


def check_permissions():
    """Verifica permisos de macOS y guia al usuario si faltan."""
    # Micrófono: intentar abrir un stream corto
    try:
        test = sd.InputStream(samplerate=16000, channels=1, dtype=np.int16)
        test.start()
        test.stop()
        test.close()
    except sd.PortAudioError:
        print("Sin acceso al microfono.")
        print("Abre: Preferencias del Sistema > Privacidad y Seguridad > Microfono")
        print("Agrega tu terminal (Terminal, iTerm, etc.) a la lista.")
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"])
        sys.exit(1)

    # Accesibilidad: intentar simular un keystroke
    ret = subprocess.run(
        ["osascript", "-e", 'tell application "System Events" to key code 0'],
        capture_output=True,
    )
    if ret.returncode != 0:
        print("Sin acceso de accesibilidad (necesario para auto-paste).")
        print("Abre: Preferencias del Sistema > Privacidad y Seguridad > Accesibilidad")
        print("Agrega tu terminal a la lista.")
        subprocess.run(["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])
        sys.exit(1)


def main():
    check_permissions()

    dictator = Dictator()
    dictator.load_model()

    def on_press(key):
        if key == keyboard.Key.cmd_r:
            if dictator.lock.acquire(blocking=False):
                try:
                    dictator.start_recording()
                except Exception:
                    dictator.lock.release()

    def on_release(key):
        if key == keyboard.Key.cmd_r:
            if not dictator.lock.locked():
                return

            def process():
                try:
                    dictator.stop_recording_and_transcribe()
                finally:
                    try:
                        dictator.lock.release()
                    except RuntimeError:
                        pass

            threading.Thread(target=process, daemon=True).start()

    listener = keyboard.Listener(on_press=on_press, on_release=on_release)
    listener.start()

    print("Escuchando teclas. Ctrl+C para salir.")
    try:
        listener.join()
    except KeyboardInterrupt:
        print("\nSaliendo.")
        listener.stop()
        sys.exit(0)


if __name__ == "__main__":
    main()
