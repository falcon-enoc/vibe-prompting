VENV_PYTHON := $(shell [ -f .venv/bin/python3 ] && echo $(CURDIR)/.venv/bin/python3 || echo python3)

.PHONY: help server-install server-dev server-test server-lint create-api-key server-start server-stop server-restart server-rebuild server-status server-logs server-download-model client-open client-build client-archive client-dmg client-clean dev test lint deploy-server deploy-install tunnel-setup tunnel-up tunnel-down tunnel-logs

help: ## Muestra los targets disponibles
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# --- Servidor ---

server-install: ## Instala dependencias del servidor en el venv actual
	cd server && pip install -e ".[dev]"

server-dev: ## Corre el servidor en modo desarrollo (auto-reload)
	cd server && PYTHONPATH=src uvicorn vibe_prompt.main:app --reload --host 0.0.0.0 --port 8420 --workers 1

server-test: ## Ejecuta los tests del servidor
	cd server && PYTHONPATH=src python -m pytest tests/ -v

server-lint: ## Lint del codigo del servidor
	cd server && python -m ruff check src/ tests/ && python -m ruff format --check src/ tests/

create-api-key: ## Genera una nueva API key
	cd server && PYTHONPATH=src $(VENV_PYTHON) -c "\
import asyncio; \
from vibe_prompt.auth import init_db, create_api_key; \
from vibe_prompt.config import Settings; \
s = Settings(); \
asyncio.run(init_db(s.API_KEY_DB)); \
key = asyncio.run(create_api_key(s.API_KEY_DB, 'cli')); \
print(f'API Key: {key}')"

# --- Cliente ---

client-open: ## Abre el proyecto Xcode del cliente
	open client/VibePrompt/VibePrompt.xcodeproj

client-build: ## Compila el cliente via xcodebuild
	xcodebuild \
		-project client/VibePrompt/VibePrompt.xcodeproj \
		-scheme VibePrompt \
		-configuration Release \
		build

DMG_NAME := VibePrompt-$(shell date +%Y%m%d).dmg

client-archive: ## Archiva el cliente para distribución
	xcodebuild archive \
		-project client/VibePrompt/VibePrompt.xcodeproj \
		-scheme VibePrompt \
		-configuration Release \
		-archivePath build/VibePrompt.xcarchive \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_ALLOWED=YES

client-dmg: client-archive ## Crea DMG del cliente
	@mkdir -p build/dmg
	@cp -R build/VibePrompt.xcarchive/Products/Applications/VibePrompt.app build/dmg/
	@test -x "$$(command -v create-dmg)" && \
		create-dmg \
			--volname "VibePrompt" \
			--window-pos 200 120 \
			--window-size 660 400 \
			--icon-size 128 \
			--text-size 14 \
			--icon "VibePrompt.app" 180 200 \
			--hide-extension "VibePrompt.app" \
			--app-drop-link 480 200 \
			--no-internet-enable \
			$$(test -f client/dmg-resources/dmg-background.png && echo "--background client/dmg-resources/dmg-background.png") \
			$$(test -f client/dmg-resources/VolumeIcon.icns && echo "--volicon client/dmg-resources/VolumeIcon.icns") \
			"build/$(DMG_NAME)" \
			"build/dmg/" || \
		hdiutil create -volname "VibePrompt" -srcfolder build/dmg -ov -format UDZO "build/$(DMG_NAME)"
	@rm -rf build/dmg
	@echo "DMG creado: build/$(DMG_NAME)"

client-clean: ## Limpia artefactos de build del cliente
	rm -rf build/

# --- Shortcuts ---

dev: server-dev ## Alias para server-dev

test: server-test ## Alias para server-test

lint: server-lint ## Alias para server-lint

# --- Gestión del servicio (ejecutar en el Mac Mini) ---

LAUNCHD_ID  := com.vibeprompt.server
LAUNCHD_GUI := gui/$(shell id -u)/$(LAUNCHD_ID)
LOG_DIR     := $(HOME)/Library/Logs/vibe-prompt

server-start: ## Inicia el servicio launchd del servidor
	launchctl bootstrap gui/$(shell id -u) $(HOME)/Library/LaunchAgents/$(LAUNCHD_ID).plist

server-stop: ## Detiene el servicio launchd del servidor
	launchctl bootout $(LAUNCHD_GUI) 2>/dev/null || true
	@echo "Servidor detenido."

server-restart: ## Reinicia el servicio launchd del servidor
	launchctl kickstart -k $(LAUNCHD_GUI)
	@echo "Servidor reiniciado."

server-rebuild: ## Pull + reinstala dependencias + reinicia el servidor
	git -C $(CURDIR) pull --ff-only
	cd server && $(CURDIR)/.venv/bin/pip install -e . --quiet
	launchctl kickstart -k $(LAUNCHD_GUI)
	@echo "Rebuild completado. Esperando arranque..."
	@sleep 3
	@curl -sf http://localhost:8420/health | python3 -m json.tool || echo "Health check falló — revisa los logs."

server-status: ## Muestra estado del servicio y health check
	@launchctl print $(LAUNCHD_GUI) 2>/dev/null | grep -E "state|pid" || echo "Servicio no registrado."
	@echo ""
	@curl -sf http://localhost:8420/health | python3 -m json.tool || echo "Servidor no responde."

server-logs: ## Sigue los logs del servidor en tiempo real
	tail -f $(LOG_DIR)/stderr.log

server-download-model: ## Descarga el modelo configurado en .env al almacenamiento local
	cd server && $(CURDIR)/.venv/bin/python -c "\
import asyncio; \
from vibe_prompt.model_manager import ModelManager; \
from vibe_prompt.config import Settings; \
from pathlib import Path; \
async def main(): \
    s = Settings(); \
    mm = ModelManager(Path(s.MODEL_STORAGE_PATH).expanduser()); \
    print(f'Descargando {s.MODEL_ID} (~2.3 GB)...'); \
    path = await mm.download(s.MODEL_ID, hf_token=s.HF_TOKEN); \
    print(f'Modelo listo en: {path}'); \
asyncio.run(main())" PYTHONPATH=src

# --- Deploy ---

deploy-server: ## Despliega el servidor al Mac Mini (requiere MAC_MINI_HOST=user@host)
	@test -n "$(MAC_MINI_HOST)" || (echo "Error: define MAC_MINI_HOST=user@host" && exit 1)
	rsync -avz \
		--exclude='.venv' \
		--exclude='__pycache__' \
		--exclude='*.pyc' \
		--exclude='data/' \
		--exclude='*.egg-info' \
		server/ $(MAC_MINI_HOST):~/vibe-prompt/server/
	rsync -avz deploy/ $(MAC_MINI_HOST):~/vibe-prompt/deploy/
	rsync -avz Makefile $(MAC_MINI_HOST):~/vibe-prompt/
	ssh $(MAC_MINI_HOST) "cd ~/vibe-prompt && make server-install"
	ssh $(MAC_MINI_HOST) "launchctl kickstart -k gui/$$(ssh $(MAC_MINI_HOST) 'id -u')/com.vibeprompt.server 2>/dev/null || true"
	@echo "Deploy completado. Verificando..."
	sleep 2
	ssh $(MAC_MINI_HOST) "curl -sf http://localhost:8420/health | python3 -m json.tool"

deploy-install: ## Provision inicial del Mac Mini (requiere MAC_MINI_HOST=user@host)
	@test -n "$(MAC_MINI_HOST)" || (echo "Error: define MAC_MINI_HOST=user@host" && exit 1)
	rsync -avz . $(MAC_MINI_HOST):~/vibe-prompt/ \
		--exclude='.git' \
		--exclude='.venv' \
		--exclude='__pycache__' \
		--exclude='*.pyc' \
		--exclude='data/'
	ssh $(MAC_MINI_HOST) "chmod +x ~/vibe-prompt/deploy/setup-mac-mini.sh && ~/vibe-prompt/deploy/setup-mac-mini.sh"

# --- Tunnel (Cloudflare) ---

tunnel-setup: ## Setup inicial del tunnel Cloudflare (interactivo)
	deploy/tunnel/setup-tunnel.sh

tunnel-up: ## Levanta el tunnel Cloudflare
	cd deploy/tunnel && docker compose up -d

tunnel-down: ## Para el tunnel Cloudflare
	cd deploy/tunnel && docker compose down

tunnel-logs: ## Muestra logs del tunnel
	cd deploy/tunnel && docker compose logs -f
