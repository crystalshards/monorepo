#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Resetting and seeding all databases"
echo "=========================================="
echo ""
echo "WARNING: This will drop all databases!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

APPS=("crystalshards" "crystaldocs" "crystalgigs" "crystalbits")

for app in "${APPS[@]}"; do
  echo "----------------------------------------"
  echo "Resetting: $app"
  echo "----------------------------------------"

  cd "$PROJECT_ROOT/apps/$app"

  if [ ! -f "lucky" ]; then
    echo "Warning: Lucky CLI not found in $app, skipping..."
    continue
  fi

  echo "Dropping database..."
  lucky db.drop || echo "Database doesn't exist, continuing..."

  echo "Creating database..."
  lucky db.create

  echo "Running migrations..."
  lucky db.migrate

  echo "Seeding data..."
  lucky db.seed.sample_data

  echo "✓ Successfully reset and seeded $app"
  echo ""
done

echo "=========================================="
echo "All databases reset and seeded!"
echo "=========================================="
echo ""
echo "Seeded data:"
echo "  - CrystalShards: 12 shards with 29 versions"
echo "  - CrystalDocs: 11 documentation packages"
echo "  - CrystalGigs: 6 job postings"
echo "  - CrystalBits: 6 blog posts"
echo ""
