#!/bin/sh
# The untrusted half of a documentation build.
#
# This container compiles a third party shard. Crystal expands macros while
# compiling, and a macro can shell out, so everything below this line should be
# read as "code the shard author can influence runs here".
#
# That is why this holds no credentials. Its service account has zero IAM
# bindings, there is no key file, and the metadata server has nothing worth
# taking. It receives exactly two capabilities, both minted by the launcher and
# both expiring in minutes:
#
#   DOCS_SOURCE_URL   signed GET, one object, the prepared source tree
#   DOCS_UPLOAD_URL   signed PUT, one object, the single artifact
#
# It cannot choose where its output lands: the object key is baked into the
# signature. Widening this container's access, for any reason, removes the
# property the whole design exists for.
#
# Kept as a shell script rather than a compiled binary of ours deliberately.
# The less of our code that shares a process with an untrusted compile, the
# smaller the thing anyone has to reason about.
set -eu

: "${DOCS_SOURCE_URL:?DOCS_SOURCE_URL is not set; the launcher must mint a signed GET for the source}"
: "${DOCS_UPLOAD_URL:?DOCS_UPLOAD_URL is not set; the launcher must mint a signed PUT for the artifact}"
: "${DOCS_UPLOAD_CONTENT_TYPE:?DOCS_UPLOAD_CONTENT_TYPE is not set; it must match what the PUT url was signed for}"

WORK_DIR="$(mktemp -d)"
cd "$WORK_DIR"

echo "docs-build: fetching source"
# --fail so an expired or wrong signature stops here rather than producing an
# error page that tar would then try to unpack.
curl --fail --silent --show-error --location --max-time 300 \
  -o source.tar.gz "$DOCS_SOURCE_URL"

mkdir -p src
tar -xzf source.tar.gz -C src
rm -f source.tar.gz

echo "docs-build: generating documentation"
cd src

# --format=json emits one document on stdout instead of writing an HTML tree.
# That single file is the entire artifact: documentation is rendered by our own
# site, and shard-authored HTML served from our origin would be stored XSS.
crystal docs --format=json > "$WORK_DIR/docs.json"

# An empty document is a failed build even when the compiler exited 0. Failing
# here means the launcher sees a failed execution rather than publishing
# nothing over something.
if [ ! -s "$WORK_DIR/docs.json" ]; then
  echo "docs-build: crystal docs produced no output" >&2
  exit 1
fi

echo "docs-build: uploading documentation"
# The content type must be byte-identical to the one the URL was signed for.
# GCS signs the content type, so a mismatch is a 403 that reads like a broken
# build. It is passed in rather than hardcoded so it cannot drift.
curl --fail --silent --show-error --max-time 300 \
  -X PUT \
  -H "Content-Type: ${DOCS_UPLOAD_CONTENT_TYPE}" \
  --upload-file "$WORK_DIR/docs.json" \
  "$DOCS_UPLOAD_URL"

echo "docs-build: done"
