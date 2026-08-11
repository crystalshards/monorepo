#!/bin/bash
set -e

echo "🚀 Starting CrystalShards services..."

# Start PostgreSQL and object storage if docker-compose.yml exists
if [ -f "/workspaces/monorepo/docker-compose.yml" ]; then
    echo "📦 Starting database services..."
    docker-compose up -d postgres minio
else
    echo "⚠️  No docker-compose.yml found, skipping service startup"
fi

echo "✅ Post-start completed!"
