# =============================================================================
# bot-cripto — atalhos. Rode `make` para ver a lista.
# Todos os comandos usam a imagem oficial via docker compose; nada roda fora do container.
# =============================================================================
SHELL := /bin/bash
COMPOSE := docker compose
FT := $(COMPOSE) run --rm freqtrade
CONFIG := /freqtrade/user_data/config.json
STRATEGY ?= $(shell grep -E '^FREQTRADE_STRATEGY=' .env 2>/dev/null | cut -d= -f2)
STRATEGY := $(if $(STRATEGY),$(STRATEGY),PlaceholderStrategy)

.DEFAULT_GOAL := help

help: ## Lista os comandos
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---- Operação ---------------------------------------------------------------
check: ## Checklist de segurança (.env, permissões, dry-run, blacklist...)
	@bash scripts/check-seguranca.sh

up: check ## Sobe o bot em segundo plano (dry-run por padrão)
	$(COMPOSE) up -d
	@echo "Bot no ar. Logs: make logs"

down: ## Para o bot
	$(COMPOSE) down

restart: ## Reinicia o bot
	$(COMPOSE) restart

logs: ## Acompanha os logs
	$(COMPOSE) logs -f --tail=200

ps: ## Estado do container e do health-check
	$(COMPOSE) ps

pull: ## Atualiza a imagem do Freqtrade (depois: make restart)
	$(COMPOSE) pull

shell: ## Abre um shell dentro do container
	$(FT) /bin/bash || $(COMPOSE) exec freqtrade /bin/bash

# ---- Diagnóstico ------------------------------------------------------------
show-config: ## Mostra a config efetiva (segredos mascarados)
	$(FT) show-config --config $(CONFIG) --strategy $(STRATEGY)

list-strategies: ## Lista estratégias disponíveis em user_data/strategies
	$(FT) list-strategies --config $(CONFIG)

list-pairs: ## Mostra os pares que a pairlist dinâmica selecionaria agora
	$(FT) test-pairlist --config $(CONFIG)

tunnel-help: ## Mostra como abrir o túnel SSH para o FreqUI
	@echo "No seu computador:  ssh -N -L 8080:127.0.0.1:8080 usuario@IP_DA_VPS"
	@echo "Depois abra:        http://localhost:8080"

# ---- Dados e testes (Fase 1 e 2) -------------------------------------------
# Exemplos:
#   make download PAIRS="BTC/USDT ETH/USDT" TF="1h 4h" DAYS=1095
#   make backtest STRATEGY=MinhaEstrategia RANGE=20240101-20250101
PAIRS ?= BTC/USDT ETH/USDT
TF    ?= 1h 4h
DAYS  ?= 1095
RANGE ?=

download: ## Baixa candles históricos (PAIRS, TF, DAYS)
	$(FT) download-data --config $(CONFIG) --exchange binance -p $(PAIRS) -t $(TF) --days $(DAYS)

backtest: ## Backtest com taxas (STRATEGY, RANGE=AAAAMMDD-AAAAMMDD)
	$(FT) backtesting --config $(CONFIG) --strategy $(STRATEGY) $(if $(RANGE),--timerange $(RANGE),) --export trades --cache none

# ---- Backup -----------------------------------------------------------------
backup: ## Backup do banco + configs em ./backups
	@bash scripts/backup.sh

.PHONY: help check up down restart logs ps pull shell show-config list-strategies list-pairs tunnel-help download backtest backup
