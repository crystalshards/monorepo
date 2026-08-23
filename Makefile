# CrystalShards Development Makefile
#
# Apps and their local dev ports:
#   crystalshards  http://localhost:3000   package registry
#   crystaldocs    http://localhost:3001   documentation hosting
#   crystalgigs    http://localhost:3002   job board
#   crystalbits    http://localhost:3003   blog and newsletter
#   trycrystal     http://localhost:3004   interactive tutorial console
#
# The tutorial console is two processes. The sandbox runner it submits code to
# listens on http://localhost:9292 and is started by `make dev` alongside the
# apps, because the console can serve pages without it and cannot run a single
# lesson. Locally the runner is asked to run loose, by name, with
# ALLOW_UNSAFE=true; it refuses to start with neither that nor a configured
# sandbox, which is the whole point of the gate.
#
# Local development needs no Google Cloud credentials. Object storage is the
# container docker compose runs; production is Google Cloud Storage, selected
# by LUCKY_ENV=production and never reachable from here.

.PHONY: help setup install-deps build start stop services migrate seed reset test lint format dev clean logs db-console docs.real docs.core runner.build runner.test

# Every Lucky application. trycrystal is here and deliberately NOT in DB_APPS
# below: it has no database, so it takes part in install, build, test, lint,
# format and dev, and must never appear in a target that creates, migrates,
# seeds or drops one.
APPS       := crystalshards crystaldocs crystalgigs crystalbits trycrystal

# The applications backed by Postgres. Everything that exists because a
# database exists iterates this instead: database creation in `services`,
# `migrate`, `seed` and `reset`. This split mirrors local.public_apps and
# local.database_apps in terraform/locals.tf, for the same reason.
DB_APPS    := crystalshards crystaldocs crystalgigs crystalbits
DB_USER    ?= postgres
DB_PASSWORD ?= password
DB_HOST    ?= localhost
DB_PORT    ?= 5432

# psql reads PGPASSWORD, not DB_PASSWORD, and the raw psql calls in
# `services` pass no password at all, so a clean shell fails with
# "no password supplied".
export PGPASSWORD ?= $(DB_PASSWORD)

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

# Object storage. The variable names are backend-neutral on purpose: the apps
# talk to one object store interface, backed by Google Cloud Storage in
# production and by the local container here. Nothing an app reads names a
# backend, so a developer never needs cloud credentials.
#
# DOCS_BUCKET is shared: CrystalShards builds documentation into it and
# CrystalDocs serves it back out, so both apps must agree. In production these
# have no defaults and a missing one stops the service at boot.
STORAGE_ENDPOINT   ?= http://localhost:9000
STORAGE_ACCESS_KEY ?= minioadmin
STORAGE_SECRET_KEY ?= minioadmin
DOCS_BUCKET        ?= crystal-docs
PACKAGES_BUCKET    ?= packages

STORAGE_ENV = STORAGE_ENDPOINT=$(STORAGE_ENDPOINT) STORAGE_ACCESS_KEY=$(STORAGE_ACCESS_KEY) \
              STORAGE_SECRET_KEY=$(STORAGE_SECRET_KEY) DOCS_BUCKET=$(DOCS_BUCKET) \
              PACKAGES_BUCKET=$(PACKAGES_BUCKET)

# Documentation builds compile third-party shard code, and Crystal runs macros
# while compiling, so `crystal docs` on a published shard executes that
# author's commands. A build refuses to run without a sandbox; locally that
# sandbox is Docker, which gives the compile no network and none of this
# machine's environment.
DOCS_SANDBOX       ?= docker
DOCS_SANDBOX_IMAGE ?= crystallang/crystal:1.21.0-alpine

SANDBOX_ENV = DOCS_SANDBOX=$(DOCS_SANDBOX) DOCS_SANDBOX_IMAGE=$(DOCS_SANDBOX_IMAGE)

# The job ad strip. CrystalShards, CrystalDocs and CrystalBits read promotable
# jobs from CrystalGigs over HTTP; unset turns the strip off rather than
# breaking the app, so it is set here to keep `make dev` showing what
# production shows. Harmless on CrystalGigs itself, which never reads it.
JOB_ADS_URL ?= http://localhost:3002/api/ads

JOB_ADS_ENV = JOB_ADS_URL=$(JOB_ADS_URL)

# The trycrystal sandbox runner. The console POSTs every submission here, and
# the URL is the same one the deployed app receives as RUNNER_URL, so a lesson
# that works locally is exercising the same client path production does.
RUNNER_PORT ?= 9292
RUNNER_URL  ?= http://localhost:$(RUNNER_PORT)

# Local development runs the sandbox loose. ALLOW_UNSAFE=true is the exact
# string the runner's gate accepts and nothing else is truthy to it: the runner
# refuses to start when confinement is neither configured nor explicitly
# waived, so there is no way to run it unconfined by accident.
#
# RUNNER_EXEC_MODE=run is here because this target runs a NATIVE binary built
# by the workstation's own Crystal, and no official Crystal distribution ships
# interpreter support: `crystal i` on this machine answers "Crystal was
# compiled without interpreter support" and exits 1. Production is the
# opposite and deliberately so, the interpreter image builds Crystal from
# source with interpreter=1 and defaults to it, so local development is
# exercising the documented escape hatch rather than the deploy shape. What
# stays identical in both is the confinement gate and the HTTP contract.
# RUNNER_CRYSTAL_BIN is deliberately unset here so run mode uses the crystal
# on PATH.
RUNNER_DEV_ENV = PORT=$(RUNNER_PORT) ALLOW_UNSAFE=true RUNNER_EXEC_MODE=run


help: ## Show this help message
	@echo "CrystalShards Development Commands:"
	@grep -E '^[a-zA-Z_.-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: services install-deps migrate seed ## Full local setup: services, deps, migrations, sample data
	@echo ""
	@echo "Setup complete. Run 'make dev' to start every app and the sandbox runner."

services: ## Start object storage and mail capture in Docker, and verify Postgres is reachable
	@echo "Starting supporting services..."
	docker compose up -d minio mailhog
	@echo "Checking Postgres at $(DB_HOST):$(DB_PORT)..."
	@pg_isready -h $(DB_HOST) -p $(DB_PORT) >/dev/null 2>&1 || \
		(echo "Postgres is not reachable at $(DB_HOST):$(DB_PORT). Start it, then re-run." && exit 1)
	@for app in $(DB_APPS); do \
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
	@echo "Ensuring buckets ($(DOCS_BUCKET), $(PACKAGES_BUCKET))..."
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		curl -sf $(STORAGE_ENDPOINT)/minio/health/live >/dev/null 2>&1 && break || sleep 2; \
	done
	@docker run --rm --network host --entrypoint sh minio/mc:latest -c \
		"mc alias set local $(STORAGE_ENDPOINT) $(STORAGE_ACCESS_KEY) $(STORAGE_SECRET_KEY) >/dev/null && \
		 mc mb --ignore-existing local/$(DOCS_BUCKET) local/$(PACKAGES_BUCKET) >/dev/null" \
		|| echo "  WARNING: could not create buckets; documentation pages will report storage unavailable."
	@echo "Buckets ready."

install-deps: ## Install Crystal dependencies for all apps
	@for app in $(APPS); do \
		echo "Installing dependencies for $$app..."; \
		(cd apps/$$app && shards install) || exit 1; \
	done

build: ## Build every application
	@for app in $(APPS); do \
		echo "Building $$app..."; \
		(cd apps/$$app && crystal build src/$$app.cr -o bin/$$app) || exit 1; \
	done

runner.build: ## Build the trycrystal sandbox runner
	@echo "Building the trycrystal runner..."
	@(cd apps/trycrystal/runner && crystal build src/main.cr -o bin/trycrystal-runner)

runner.test: ## Prove the trycrystal runner's confinement (needs Docker)
	@echo "Proving runner confinement. This builds container images and takes a while."
	@(cd apps/trycrystal/runner && crystal spec spec/confinement_spec.cr)
	@echo ""
	@echo "A local pass here is encouraging and is not the gate: uid and filesystem"
	@echo "semantics differ inside macOS Docker's VM. CI runs this same spec on Linux"
	@echo "against the image it builds, and fails the build when any example pends."

migrate: ## Run database migrations for all apps
	@for app in $(DB_APPS); do \
		echo "Migrating $$app..."; \
		(cd apps/$$app && DATABASE_URL="postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$${app}_development" \
			crystal run tasks.cr -- db.migrate) || exit 1; \
	done

seed: ## Load sample development data for all apps
	@for app in $(DB_APPS); do \
		echo "Seeding $$app..."; \
		(cd apps/$$app && DATABASE_URL="postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$${app}_development" \
			$(STORAGE_ENV) \
			crystal run tasks.cr -- db.seed.sample_data) || exit 1; \
	done

docs.real: ## Generate real shard docs in the sandbox and upload to object storage (scripts/build_real_docs.sh)
	@$(STORAGE_ENV) ./scripts/build_real_docs.sh
	@echo ""
	@echo "Re-run 'make seed' to sync crystaldocs rows with what is now in storage."

docs.core: ## Build and publish the Crystal standard library's own documentation (scripts/build_core_docs.sh)
	@./scripts/build_core_docs.sh

reset: ## Drop, recreate, migrate and seed every development database
	@for app in $(DB_APPS); do \
		psql -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER) -d postgres -q -c \
			"DROP DATABASE IF EXISTS $${app}_development"; \
	done
	@$(MAKE) services migrate seed

test: ## Run the spec suite for all apps
	@for app in $(APPS); do \
		echo "Running specs for $$app..."; \
		(cd apps/$$app && DATABASE_URL="postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$${app}_test" \
			$(STORAGE_ENV) \
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

dev: ## Run every app plus the trycrystal sandbox runner (Ctrl-C stops everything)
	@for app in $(APPS); do \
		[ -x apps/$$app/bin/$$app ] || { $(MAKE) build; break; }; \
	done
	@[ -x apps/trycrystal/runner/bin/trycrystal-runner ] || $(MAKE) runner.build
	@echo "crystalshards  http://localhost:3000"
	@echo "crystaldocs    http://localhost:3001"
	@echo "crystalgigs    http://localhost:3002"
	@echo "crystalbits    http://localhost:3003"
	@echo "trycrystal     http://localhost:3004"
	@echo "runner         $(RUNNER_URL)  (unconfined, local only)"
	@echo ""
	@trap 'kill 0' EXIT INT TERM; \
	(cd apps/trycrystal/runner && $(RUNNER_DEV_ENV) \
		./bin/trycrystal-runner 2>&1 | sed "s/^/[runner] /") & \
	port=3000; \
	for app in $(APPS); do \
		case $$app in \
			trycrystal) db_env=""; app_env="RUNNER_URL=$(RUNNER_URL)" ;; \
			*) db_env="DATABASE_URL=postgresql://$(DB_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$${app}_development"; app_env="" ;; \
		esac; \
		(cd apps/$$app && env DEV_PORT=$$port \
			$$db_env \
			$$app_env \
			$(STORAGE_ENV) \
			$(SANDBOX_ENV) \
			$(JOB_ADS_ENV) \
			./bin/$$app 2>&1 | sed "s/^/[$$app] /") & \
		port=$$((port + 1)); \
	done; \
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
