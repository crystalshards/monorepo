#!/usr/bin/env bash
#
# Builds documentation for the Crystal standard library and publishes it as
# the `crystal` package, so core types resolve to pages on this site instead
# of linking out to crystal-lang.org.
#
# This used to run the whole recipe itself: clone, invoke the compiler,
# validate, then shell out to `docker run minio/mc` to publish. That worked on
# a laptop and nowhere else, which was the problem: nothing in production ever
# ran it, so the `crystal` key held nothing there and every core cross link on
# the live site rendered as plain text.
#
# The recipe did not change; where it lives did. It is now
# CrystalShards::CoreDocs (apps/crystalshards/src/services/core_docs.cr), and
# every reason each step exists is documented there rather than restated here:
#
#   * CRYSTAL_PATH must point at the CLONE's src and lib, not the installed
#     compiler's, or the standard library loads twice and the build dies on
#     "already initialized constant Array::SMALL_ARRAY_SIZE"
#   * --project-name and --project-version are required, since the Crystal
#     repository has no shard.yml to infer them from
#   * an artifact that parses but is missing the most referenced types in the
#     language is refused rather than published, because it would turn every
#     core cross link into plain text with nothing to say why
#
# Publishing now goes through CrystalShards::StorageService, the same object
# store interface apps/crystalshards uses for a shard's documentation, rather
# than a container shelling out to `mc`. Registration and the build status
# that makes a version readable on the site go through the same
# CrystalShards::DocsBuildStatus a shard build already uses: there is no
# second "make seed" step to remember, because this script's own run leaves
# the database exactly where a production build would.
#
# In production the identical code runs inside the docs-build-core Cloud Run
# Job, reached through docs-launcher when a build request names the `crystal`
# package. This script drives the same CrystalShards::CoreDocs entrypoint
# (src/publish_core_docs.cr) locally and unsandboxed, which is the one thing
# production never does: `crystal docs` still expands Crystal's own macros,
# including llvm.cr shelling out to llvm-config, and running that with no
# confinement is a choice this script is allowed to make about this machine
# and production is not allowed to make about a Cloud Run Job.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$here/apps/crystalshards"

# Local object storage and databases, the same backend-neutral names and
# defaults every other script and the Makefile use. This script is a
# development tool; production never sets DOCS_SANDBOX_ALLOW_UNSAFE and never
# reaches this file.
export STORAGE_ENDPOINT="${STORAGE_ENDPOINT:-http://localhost:9000}"
export STORAGE_ACCESS_KEY="${STORAGE_ACCESS_KEY:-minioadmin}"
export STORAGE_SECRET_KEY="${STORAGE_SECRET_KEY:-minioadmin}"
export DOCS_BUCKET="${DOCS_BUCKET:-crystal-docs}"
export DATABASE_URL="${DATABASE_URL:-postgresql://postgres:password@localhost:5432/crystalshards_development}"
export DOCS_DATABASE_URL="${DOCS_DATABASE_URL:-postgresql://postgres:password@localhost:5432/crystaldocs_development}"

# The one sandbox choice available outside production. CoreDocs.build_and_publish
# refuses to run without it being made explicitly; see the comment on
# CrystalShards::CoreDocs.resolve_sandbox for why docker is not offered here
# (that sandbox image carries no LLVM).
export DOCS_SANDBOX="${DOCS_SANDBOX:-none}"
export DOCS_SANDBOX_ALLOW_UNSAFE="${DOCS_SANDBOX_ALLOW_UNSAFE:-true}"

echo "Building and publishing the Crystal standard library's documentation..."
echo "  compiler: $(crystal --version | head -1)"
echo "  storage:  ${STORAGE_ENDPOINT} (bucket ${DOCS_BUCKET})"
echo "  database: ${DOCS_DATABASE_URL}"
echo ""

exec crystal run src/publish_core_docs.cr
