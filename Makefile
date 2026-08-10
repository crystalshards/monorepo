# CrystalShards Development Makefile
#
# Apps and their local dev ports:
#   crystalshards  http://localhost:3000   package registry
#   crystaldocs    http://localhost:3001   documentation hosting
#   crystalgigs    http://localhost:3002   job board
#   crystalbits    http://localhost:3003   blog and newsletter

.PHONY: help setup install-deps build start stop services migrate seed reset test lint format dev clean logs db-console

APPS       := crystalshards crystaldocs crystalgigs crystalbits
DB_USER    ?= postgres
DB_PASSWORD ?= postgres
DB_HOST    ?= localhost
DB_PORT    ?= 5432

# Crystal's stdlib links against OpenSSL 3. A machine whose global
# PKG_CONFIG_PATH points at openssl@1.1 fails to link with missing EVP_*
# symbols, so put OpenSSL 3 first when it is present. Prepending (not ?=)
# matters: an inherited openssl@1.1 entry would otherwise win.
OPENSSL3_PKGCONFIG := $(firstword $(wildcard /opt/homebrew/opt/openssl@3/lib/pkgconfig /usr/local/opt/openssl@3/lib/pkgconfig))
ifneq ($(OPENSSL3_PKGCONFIG),)
export PKG_CONFIG_PATH := $(OPENSSL3_PKGCONFIG):$(PKG_CONFIG_PATH)
endif

# Local development runs without Stripe credentials. This is explicit, never a
# silent fallback: CrystalGigs refuses to boot in payment mode without a key.
export PAYMENTS_DISABLED ?= true

define app_db_url
postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$(1)_development
endef

define app_test_db_url
postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$(1)_test
endef

help: ## Show this help message
	@echo "CrystalShards Development Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: services install-deps migrate seed ## Full local setup: services, deps, migrations, sample data
	@echo ""
	@echo "Setup complete. Run 'make dev' to start all four apps."

services: ## Start Redis and MinIO in Docker, and verify Postgres is reachable
	@echo "Starting supporting services..."
	docker compose up -d redis minio mailhog
	@echo "Checking Postgres at $(DB_HOST):$(DB_PORT)..."
	@pg_isready -h $(DB_HOST) -p $(DB_PORT) >/dev/null 2>&1 || \
		(echo "Postgres is not reachable at $(DB_HOST):$(DB_PORT). Start it, then re-run." && exit 1)
	@for app in $(APPS); do \
		psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d postgres -tAc \
			"SELECT 1 FROM pg_database WHERE datname='$${app}_development'" | grep -q 1 || \
		psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d postgres -q -c \
			"CREATE DATABASE $${app}_development OWNER $(DB_USER)"; \
		psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d postgres -tAc \
			"SELECT 1 FROM pg_database WHERE datname='$${app}_test'" | grep -q 1 || \
		psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d postgres -q -c \
			"CREATE DATABASE $${app}_test OWNER $(DB_USER)"; \
	done
	@echo "Databases ready."

install-deps: ## Install Crystal dependencies for all apps
	@for app in $(APPS); do \
		echo "Installing dependencies for $$app..."; \
		(cd apps/$$app && shards install) || exit 1; \
	done

build: ## Build all applications and the background worker
	@for app in $(APPS); do \
		echo "Building $$app..."; \
		(cd apps/$$app && crystal build src/$$app.cr -o bin/$$app) || exit 1; \
	done
	@echo "Building crystalshards worker..."
	@cd apps/crystalshards && crystal build src/worker.cr -o bin/worker

migrate: ## Run database migrations for all apps
	@for app in $(APPS); do \
		echo "Migrating $$app..."; \
		(cd apps/$$app && DATABASE_URL="postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$${app}_development" \
			crystal run tasks.cr -- db.migrate) || exit 1; \
	done

seed: ## Load sample development data for all apps
	@for app in $(APPS); do \
		echo "Seeding $$app..."; \
		(cd apps/$$app && DATABASE_URL="postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$${app}_development" \
			crystal run tasks.cr -- db.seed.sample_data) || exit 1; \
	done

reset: ## Drop, recreate, migrate and seed every development database
	@for app in $(APPS); do \
		psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d postgres -q -c \
			"DROP DATABASE IF EXISTS $${app}_development"; \
	done
	@$(MAKE) services migrate seed

test: ## Run the spec suite for all apps
	@for app in $(APPS); do \
		echo "Running specs for $$app..."; \
		(cd apps/$$app && DATABASE_URL="postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$${app}_test" \
			MINIO_ENDPOINT=http://localhost:9000 MINIO_ACCESS_KEY=minioadmin \
			MINIO_SECRET_KEY=minioadmin MINIO_BUCKET=test-bucket \
			crystal spec) || exit 1; \
	done

lint: ## Run ameba across all apps
	@for app in $(APPS); do \
		echo "Linting $$app..."; \
		(cd apps/$$app && ameba src/) || exit 1; \
	done

format: ## Format all Crystal source
	@for app in $(APPS); do \
		crystal tool format apps/$$app/src apps/$$app/spec; \
	done

dev: ## Run all four apps and the background worker (Ctrl-C stops everything)
	@echo "crystalshards  http://localhost:3000"
	@echo "crystaldocs    http://localhost:3001"
	@echo "crystalgigs    http://localhost:3002"
	@echo "crystalbits    http://localhost:3003"
	@echo "worker         JoobQ queues: index, docs, deps"
	@echo ""
	@trap 'kill 0' EXIT INT TERM; \
	port=3000; \
	for app in $(APPS); do \
		(cd apps/$$app && DEV_PORT=$$port \
			DATABASE_URL="postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$${app}_development" \
			REDIS_URL=redis://localhost:6379/0 \
			MINIO_ENDPOINT=http://localhost:9000 MINIO_ACCESS_KEY=minioadmin MINIO_SECRET_KEY=minioadmin \
			./bin/$$app 2>&1 | sed "s/^/[$$app] /") & \
		port=$$((port + 1)); \
	done; \
	(cd apps/crystalshards && \
		DATABASE_URL="postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/crystalshards_development" \
		REDIS_URL=redis://localhost:6379/0 \
		MINIO_ENDPOINT=http://localhost:9000 MINIO_ACCESS_KEY=minioadmin MINIO_SECRET_KEY=minioadmin \
		./bin/worker 2>&1 | sed "s/^/[worker] /") & \
	wait

stop: ## Stop supporting Docker services
	docker compose down

logs: ## Tail supporting service logs
	docker compose logs -f

db-console: ## Open a psql console against the crystalshards development database
	psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d crystalshards_development

clean: ## Remove build artifacts and installed shards
	rm -rf apps/*/bin apps/*/lib
	docker compose down -v
