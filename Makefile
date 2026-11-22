# Run these on the Pi, from the project directory.
.DEFAULT_GOAL := help
SHELL := /bin/bash

-include .env
DATA_DIR ?= ./data
BACKUP_DIR ?= ./backups

.PHONY: help setup build up down restart wait logs status update backup backups restore shell box-versions \
        backup-delete restore-world worlds world-switch world-delete world-export world-import \
        players player admins settings errors clean-images

help: ## Show this help
	@# Only this file: MAKEFILE_LIST also holds .env, and grep would prefix filenames.
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | awk -F':.*## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup: ## One-time host checks, .env creation, swap, directories
	@./scripts/setup-host.sh

build: ## Build the arm64 server image (takes a while the first time)
	docker compose build --pull

dirs:
	@mkdir -p "$(DATA_DIR)/worlds" "$(BACKUP_DIR)"

up: dirs ## Start server + backup sidecar in the background
	docker compose up -d

down: ## Stop everything (server saves the world first)
	docker compose down

restart: ## Restart the server: applies .env changes, checks for a Valheim update
	@# Recreate, not `docker compose restart`: a restart keeps the container's old
	@# environment, so .env changes (ADMIN_IDS, WORLD_*, ...) would be ignored.
	docker compose up -d --force-recreate valheim

wait: ## Wait until the server is joinable (e.g. make up && make wait)
	@echo "Waiting until the server is joinable (Ctrl-C stops waiting, not the server)..."
	@for i in $$(seq 1 200); do \
	  [ "$$(docker inspect -f '{{.State.Running}}' valheim 2>/dev/null)" = true ] \
	    || { echo "The server container isn't running. Check: make logs"; exit 1; }; \
	  case "$$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' valheim)" in \
	    healthy)   echo "Ready: join at $$(hostname -I | awk '{print $$1}'):2456"; exit 0 ;; \
	    unhealthy) echo "The server is unhealthy. Check: make logs"; exit 1 ;; \
	  esac; \
	  sleep 10; \
	done; \
	echo "Still not joinable after about 33 minutes. Check: make logs"; exit 1

logs: ## Follow server logs
	docker compose logs -f --tail=200 valheim

status: ## Containers, health, CPU/RAM use, Pi temperature
	@docker compose ps
	@docker stats --no-stream valheim valheim-backup 2>/dev/null || true
	@command -v vcgencmd >/dev/null && vcgencmd measure_temp && vcgencmd get_throttled || true

update: ## Rebuild image with latest box64 and restart (updates Valheim too)
	docker compose build --pull --no-cache valheim
	docker compose up -d valheim

backup: dirs ## Take a snapshot backup right now
	docker compose run --rm --no-deps backup /bin/sh /scripts/backup-once.sh

backups: ## List all backups, total size and free space
	@./scripts/admin.sh backups

backup-delete: ## Delete one backup (asks): make backup-delete FILE=backups/...
	@./scripts/admin.sh backup-delete "$(FILE)"

restore: ## Restore ALL worlds from a snapshot: make restore FILE=backups/worlds-....tar.gz
	@./scripts/restore.sh "$(FILE)"

restore-world: ## Restore ONE world from a snapshot: FILE=backups/worlds-... NAME=<world>
	@./scripts/admin.sh restore-world "$(FILE)" "$(NAME)"

# ---------------------------------------------------------------- worlds ----
worlds: ## List worlds (* = active), size, last save
	@./scripts/admin.sh worlds

world-switch: ## Switch to a world, or create a new one: make world-switch NAME=<world>
	@./scripts/admin.sh world-switch "$(NAME)"

world-delete: ## Delete a world (you type its name to confirm): NAME=<world>
	@./scripts/admin.sh world-delete "$(NAME)"

world-export: ## Pack one world into BACKUP_DIR: NAME=<world>
	@./scripts/admin.sh world-export "$(NAME)"

world-import: ## Add a world from an export or a world folder: FILE=<path>
	@./scripts/admin.sh world-import "$(FILE)"

# ----------------------------------------------------------------- admin ----
players: ## Players connected now, recent activity, known players
	@./scripts/admin.sh players

player: ## One player's history and Steam profile: ID=<SteamID> or NAME="<character>"
	@./scripts/admin.sh player "$(or $(ID),$(NAME))"

admins: ## Admin, ban and permit lists
	@./scripts/admin.sh admins

settings: ## Show .env with the password hidden (safe to share)
	@./scripts/admin.sh settings

errors: ## Server errors only, known harmless noise hidden (LINES=5000)
	@./scripts/admin.sh errors "$(or $(LINES),5000)"

clean-images: ## Remove unused old Docker images (asks)
	@./scripts/admin.sh clean-images

shell: ## Shell inside the running server container
	docker compose exec valheim bash

box-versions: ## List box64 versions available to pin in .env (for your EMULATOR_BUILD)
	docker compose run --rm --no-deps --user 0 --entrypoint bash valheim -c \
	  'apt-get update -qq >/dev/null; apt-cache madison "$$(cat /etc/box64-package 2>/dev/null || echo box64-rpi4arm64)"'
