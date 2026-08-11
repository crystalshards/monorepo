#!/usr/bin/env bash
#
# Builds documentation for the Crystal standard library and publishes it as
# the `crystal` package, so core types resolve to pages on this site instead
# of linking out to crystal-lang.org.
#
# The standard library needs a different invocation from a shard, and each
# difference is load bearing:
#
#   * the entrypoint is src/docs_main.cr, which requires the whole library
#   * CRYSTAL_PATH must point at the CLONE's src, not the installed compiler's.
#     Without it the prelude resolves to the installed standard library while
#     docs_main.cr requires the clone's, both get loaded, and the build dies on
#     "already initialized constant Array::SMALL_ARRAY_SIZE"
#   * --project-name and --project-version are required, since the Crystal
#     repository has no shard.yml to infer them from
#
# Unlike a shard build this is NOT sandboxed, and that exception is only
# defensible because the input cannot be anything other than the Crystal
# compiler's own source at a pinned tag from its official repository, which
# is the same code already running this script. The URL is therefore a
# constant with no environment override: making it configurable would turn a
# reasoned exception into an arbitrary code execution switch.
set -euo pipefail

readonly REPO="https://github.com/crystal-lang/crystal.git"
readonly PACKAGE="crystal"

VERSION="${1:-$(crystal --version | head -1 | awk '{print $2}')}"

: "${MINIO_ENDPOINT:?set MINIO_ENDPOINT (make docs.core passes it)}"
: "${MINIO_ACCESS_KEY:?set MINIO_ACCESS_KEY, this script will not guess credentials}"
: "${MINIO_SECRET_KEY:?set MINIO_SECRET_KEY, this script will not guess credentials}"
DOCS_BUCKET="${MINIO_DOCS_BUCKET:-crystal-docs}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "Building Crystal ${VERSION} standard library documentation..."

if ! git clone --depth 1 --branch "$VERSION" --quiet "$REPO" "$workdir/crystal" 2>/dev/null; then
  echo "  could not clone ${REPO} at tag ${VERSION}" >&2
  exit 1
fi

artifact="$workdir/docs.json"

if ! (cd "$workdir/crystal" && CRYSTAL_PATH="$workdir/crystal/src:$workdir/crystal/lib" \
      crystal docs --format=json \
        --project-name="$PACKAGE" \
        --project-version="$VERSION" \
        src/docs_main.cr > "$artifact" 2>"$workdir/build.log"); then
  echo "  build failed:" >&2
  tail -5 "$workdir/build.log" >&2
  exit 1
fi

if [ ! -s "$artifact" ]; then
  echo "  build produced no documentation" >&2
  exit 1
fi

# `crystal docs` can exit 0 having written something unusable, and a core
# artifact that is missing the most referenced types in the language would
# quietly turn every core cross link into plain text. Check before publishing.
if ! python3 - "$artifact" <<'PY'
import json, sys

document = json.load(open(sys.argv[1]))

def walk(types, found):
    for type in types or []:
        name = type["full_name"]
        found.add(name.split("(")[0].strip())
        walk(type.get("types"), found)
    return found

names = walk(document["program"].get("types"), set())
required = ["Array", "String", "Hash", "Int32", "IO", "Enumerable",
            "Comparable", "Indexable::Mutable", "HTTP::Server", "JSON::Any"]
missing = [name for name in required if name not in names]

if missing:
    print(f"  artifact is incomplete, missing: {', '.join(missing)}", file=sys.stderr)
    sys.exit(1)

print(f"  {len(names)} types, including every required core type")
PY
then
  exit 1
fi

docker run --rm --network host -v "$workdir:/in:ro" --entrypoint sh minio/mc:latest -c \
  "mc alias set local ${MINIO_ENDPOINT} ${MINIO_ACCESS_KEY} ${MINIO_SECRET_KEY} >/dev/null && \
   mc mb --ignore-existing local/${DOCS_BUCKET} >/dev/null && \
   mc cp --quiet /in/docs.json local/${DOCS_BUCKET}/${PACKAGE}/${VERSION}/docs.json >/dev/null"

printf '%-14s %-15s %8s bytes  ok\n' "$PACKAGE" "$VERSION" "$(wc -c < "$artifact" | tr -d ' ')"
echo ""
echo "Run 'make seed' to register it, then core types link to /docs/${PACKAGE}/${VERSION}/..."
