#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Seeding all CrystalShards applications"
echo "=========================================="
echo ""

APPS=("crystalshards" "crystaldocs" "crystalgigs" "crystalbits")

for app in "${APPS[@]}"; do
  echo "----------------------------------------"
  echo "Seeding: $app"
  echo "----------------------------------------"

  cd "$PROJECT_ROOT/apps/$app"

  if [ ! -f "lucky" ]; then
    echo "Warning: Lucky CLI not found in $app, skipping..."
    continue
  fi

  if lucky db.seed.sample_data; then
    echo "✓ Successfully seeded $app"
  else
    echo "✗ Failed to seed $app"
    exit 1
  fi

  echo ""
done

echo "=========================================="
echo "All applications seeded successfully!"
echo "=========================================="
echo ""
echo "Seeded data:"
echo "  - CrystalShards: 12 shards with 29 versions"
echo "  - CrystalDocs: 11 documentation packages"
echo "  - CrystalGigs: 6 job postings"
echo "  - CrystalBits: 6 blog posts"
echo ""
