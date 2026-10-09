# Atajos para operar el relay con Docker (no hace falta Node ni Wrangler en la Mac).
RUN   = docker compose run --rm wrangler
RUN_T = docker compose run --rm -T wrangler   # sin TTY: para pasar archivos por stdin
URL  ?= $(shell cat .relay-url 2>/dev/null)

.PHONY: help build whoami deploy secret-webhook secret-app-id secret-key secrets-list tail check

help:            ## Lista los comandos
	@grep -E '^[a-z-]+:.*##' Makefile | sed 's/:.*##/ —/'

build:           ## Construye la imagen de Wrangler
	docker compose build

whoami:          ## Verifica que el token de Cloudflare funciona
	$(RUN) whoami

deploy:          ## Despliega el relay
	$(RUN) deploy

secret-webhook:  ## Carga GITHUB_WEBHOOK_SECRET (te lo pide oculto)
	$(RUN) secret put GITHUB_WEBHOOK_SECRET

secret-app-id:   ## Carga GITHUB_APP_ID. Uso: make secret-app-id APP_ID=5251683
	@test -n "$(APP_ID)" || (echo "Falta APP_ID=..."; exit 1)
	echo "$(APP_ID)" | $(RUN_T) secret put GITHUB_APP_ID

secret-key:      ## Carga la clave PKCS#8. Uso: make secret-key KEY=~/ruta/devflow-pkcs8.pem
	@test -f "$(KEY)" || (echo "No encuentro KEY=$(KEY)"; exit 1)
	@head -1 "$(KEY)" | grep -q "BEGIN PRIVATE KEY" || (echo "La clave no es PKCS#8 (paso 3.3)"; exit 1)
	$(RUN_T) secret put GITHUB_APP_PRIVATE_KEY < "$(KEY)"

secrets-list:    ## Lista los secrets cargados (sin valores)
	$(RUN) secret list

tail:            ## Ve en vivo los requests que llegan al relay (Ctrl+C para salir)
	$(RUN) tail --format pretty

check:           ## Prueba GET y POST sin firma. Uso: make check URL=https://...
	@test -n "$(URL)" || (echo "Falta URL=https://devflow-relay....workers.dev"; exit 1)
	@echo "GET  -> $$(curl -s $(URL))"
	@echo "POST -> $$(curl -s -X POST -d '{}' $(URL))"
