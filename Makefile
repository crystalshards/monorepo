# CrystalShards Development Makefile

.PHONY: help setup build start stop test clean lint format install-deps migrate

# Default target
help: ## Show this help message
	@echo "CrystalShards Development Commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Initial setup for development
	@echo "Setting up CrystalShards development environment..."
	cp .env.example .env
	@echo "Please edit .env file with your configuration"
	@echo "Then run: make start"

install-deps: ## Install Crystal dependencies for all apps
	@echo "Installing dependencies for shards-registry..."
	cd apps/shards-registry && shards install
	@echo "Installing dependencies for shards-docs..."
	cd apps/shards-docs && shards install
	@echo "Installing dependencies for gigs..."
	cd apps/gigs && shards install
	@echo "Installing dependencies for worker..."
	cd apps/worker && shards install
	@echo "Installing dependencies for shared models..."
	cd libraries/models && shards install

build: ## Build all Crystal applications
	@echo "Building shards-registry..."
	cd apps/shards-registry && shards build --production
	@echo "Building shards-docs..."
	cd apps/shards-docs && shards build --production
	@echo "Building gigs..."
	cd apps/gigs && shards build --production
	@echo "Building worker..."
	cd apps/worker && shards build --production

start: ## Start all services with Docker Compose
	@echo "Starting all services..."
	docker-compose up -d postgres redis minio mailhog
	@echo "Waiting for services to be healthy..."
	sleep 10
	@echo "Running database migrations..."
	make migrate
	@echo "Starting applications..."
	docker-compose up shards-registry shards-docs gigs worker

stop: ## Stop all services
	@echo "Stopping all services..."
	docker-compose down

restart: ## Restart all services
	make stop
	make start

migrate: ## Run database migrations
	@echo "Running migrations..."
	docker-compose exec postgres psql -U postgres -d crystalshards_development -f /docker-entrypoint-initdb.d/001_create_users.sql || true
	docker-compose exec postgres psql -U postgres -d crystalshards_development -f /docker-entrypoint-initdb.d/002_create_shards.sql || true
	docker-compose exec postgres psql -U postgres -d crystalshards_development -f /docker-entrypoint-initdb.d/003_create_shard_versions.sql || true
	docker-compose exec postgres psql -U postgres -d crystalshards_development -f /docker-entrypoint-initdb.d/004_create_job_postings.sql || true
	docker-compose exec postgres psql -U postgres -d crystalshards_development -f /docker-entrypoint-initdb.d/005_create_documentation.sql || true
	docker-compose exec postgres psql -U postgres -d crystalshards_development -f /docker-entrypoint-initdb.d/006_create_api_keys.sql || true
	docker-compose exec postgres psql -U postgres -d crystalshards_development -f /docker-entrypoint-initdb.d/007_create_search_queries.sql || true

test: ## Run tests for all applications
	@echo "Running tests for shards-registry..."
	cd apps/shards-registry && crystal spec
	@echo "Running tests for shards-docs..."
	cd apps/shards-docs && crystal spec
	@echo "Running tests for gigs..."
	cd apps/gigs && crystal spec
	@echo "Running tests for worker..."
	cd apps/worker && crystal spec
	@echo "Running tests for shared models..."
	cd libraries/models && crystal spec

lint: ## Run linting for all Crystal files
	@echo "Running ameba linter..."
	cd apps/shards-registry && ameba src/
	cd apps/shards-docs && ameba src/
	cd apps/gigs && ameba src/
	cd apps/worker && ameba src/
	cd libraries/models && ameba src/

format: ## Format all Crystal files
	@echo "Formatting Crystal files..."
	crystal tool format apps/shards-registry/src/
	crystal tool format apps/shards-docs/src/
	crystal tool format apps/gigs/src/
	crystal tool format apps/worker/src/
	crystal tool format libraries/models/src/

clean: ## Clean up build artifacts and containers
	@echo "Cleaning up..."
	docker-compose down -v
	docker system prune -f
	rm -rf apps/*/bin/
	rm -rf apps/*/lib/

logs: ## Show logs for all services
	docker-compose logs -f

logs-registry: ## Show logs for shards registry
	docker-compose logs -f shards-registry

logs-docs: ## Show logs for docs service
	docker-compose logs -f shards-docs

logs-gigs: ## Show logs for gigs service
	docker-compose logs -f gigs

logs-worker: ## Show logs for worker service
	docker-compose logs -f worker

db-console: ## Connect to PostgreSQL console
	docker-compose exec postgres psql -U postgres -d crystalshards_development

redis-console: ## Connect to Redis console
	docker-compose exec redis redis-cli

minio-console: ## Open MinIO console
	@echo "MinIO Console: http://localhost:9001"
	@echo "Username: minioadmin"
	@echo "Password: minioadmin"

mailhog: ## Open MailHog console
	@echo "MailHog Console: http://localhost:8025"

dev: ## Start development environment
	@echo "Starting development environment..."
	@echo "Registry: http://localhost:3000"
	@echo "Docs: http://localhost:3001"
	@echo "Gigs: http://localhost:3002"
	@echo "MailHog: http://localhost:8025"
	@echo "MinIO: http://localhost:9001"
	make start