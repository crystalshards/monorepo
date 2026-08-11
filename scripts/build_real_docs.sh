#!/bin/bash
#
# build_real_docs.sh - generate REAL Crystal documentation for shards and
# upload it to MinIO.
#
# Usage:
#   scripts/build_real_docs.sh                      Build the default shard set
#   scripts/build_real_docs.sh NAME REPO_URL TAG    Build a single shard
#
# `crystal docs` EXECUTES code from the shard being documented: a top-level
# macro run statement ({% `...` %}) in shard source runs shell commands at
# compile time. The docs build therefore never runs on the host. It runs in a
# locked-down Docker container: no network, no host environment, dropped
# capabilities, read-only rootfs, non-root user. Keep every one of those
# flags; they are the containment, not decoration.
#
# Trusted steps (git clone, shards install --skip-postinstall) run on the
# host: they need network but execute no code from the shard.

set -uo pipefail

# Local object storage, reached with the same backend-neutral names the apps
# use. This script is a development tool and never runs against production.
STORAGE_ENDPOINT="${STORAGE_ENDPOINT:-http://localhost:9000}"
STORAGE_ACCESS_KEY="${STORAGE_ACCESS_KEY:-minioadmin}"
STORAGE_SECRET_KEY="${STORAGE_SECRET_KEY:-minioadmin}"
DOCS_BUCKET="${DOCS_BUCKET:-crystal-docs}"
SANDBOX_IMAGE="${DOCS_SANDBOX_IMAGE:-crystallang/crystal:1.21.0-alpine}"
MC_IMAGE="${MC_IMAGE:-minio/mc:latest}"

# Wall clock limit for one untrusted docs build, matching the application
# side DocsSandbox contract. A build that outlives it is killed.
DOCS_SANDBOX_TIMEOUT_SECONDS="${DOCS_SANDBOX_TIMEOUT_SECONDS:-900}"

# name repo-url tag — one pinned, real tag per shard. The crystaldocs seed
# (tasks/db/seed/sample_data.cr) seeds rows for exactly these versions, so
# keep the two lists in lockstep.
DEFAULT_PACKAGES=(
  "kemal https://github.com/kemalcr/kemal v1.6.0"
  "amber https://github.com/amberframework/amber v1.5.0"
  "lucky https://github.com/luckyframework/lucky v1.5.0"
  "granite https://github.com/amberframework/granite v0.23.4"
  "jennifer https://github.com/imdrasil/jennifer.cr v0.13.0"
  "ameba https://github.com/crystal-ameba/ameba v1.6.4"
  "spectator https://github.com/icy-arctic-fox/spectator v0.12.4"
  "crystal-pg https://github.com/will/crystal-pg v0.30.0"
  "crystal-redis https://github.com/stefanwille/crystal-redis v2.9.1"
  "jwt https://github.com/crystal-community/jwt v1.7.2"
  "spec-kemal https://github.com/kemalcr/spec-kemal v1.3.0"
)

succeeded=0
failed=0
failures=()

# Print the tag that actually exists on the remote for the requested one.
# Shards tag releases both ways (1.2.3 and v1.2.3), so try the request as
# given first, then with a leading v.
resolve_tag() {
  local repo="$1" tag="$2"
  if git ls-remote --exit-code --tags "$repo" "refs/tags/$tag" >/dev/null 2>&1; then
    echo "$tag"
    return 0
  fi
  if git ls-remote --exit-code --tags "$repo" "refs/tags/v$tag" >/dev/null 2>&1; then
    echo "v$tag"
    return 0
  fi
  return 1
}

# Run `crystal docs` for the cloned source inside the locked-down sandbox.
# $1: source dir (mounted read-only), $2: output dir (mounted read-write),
# $3: work dir (mounted read-write), $4: path the watchdog touches when the
# build had to be killed for exceeding the wall clock limit.
#
# --format=json writes the documentation to stdout instead of writing an
# HTML tree, so the shell redirects it into the output mount. That one file
# is the whole artifact: crystaldocs renders documentation itself and never
# stores shard-authored HTML.
#
# /work is a fresh, empty host scratch dir bind-mounted in, not a tmpfs:
# `crystal docs` compiles a helper binary for every macro `run` in the shard
# and executes it, and executing a freshly written file from a tmpfs fails
# (EPERM) in local Docker VMs. Same reason /tmp is not noexec: exec from the
# container's own scratch is a legitimate language feature, and confinement
# here comes from --network none, the dropped capabilities, the read-only
# rootfs, and the non-root user, not from blocking exec.
sandboxed_crystal_docs() {
  local src="$1" out="$2" work="$3" timed_out_file="$4"
  local name="docs-sandbox-$$-$RANDOM"
  local watchdog rc

  # macOS has no GNU timeout, so a watchdog subshell enforces the wall clock
  # limit: it records the timeout and then force-removes the container, which
  # fails the docker run below. The flag is written BEFORE the kill so that by
  # the time docker run returns, the flag's presence is settled: it is there
  # if and only if the watchdog initiated the kill.
  (
    sleep "$DOCS_SANDBOX_TIMEOUT_SECONDS"
    touch "$timed_out_file"
    docker rm -f "$name" >/dev/null 2>&1
  ) &
  watchdog=$!

  docker run --rm --name "$name" --network none --read-only \
    --tmpfs /tmp:rw,nosuid,size=256m,mode=1777 \
    -v "$work:/work:rw" \
    --pids-limit 256 --memory 2g --cpus 2 \
    --cap-drop ALL --security-opt no-new-privileges \
    --user 1000:1000 -e HOME=/work \
    -v "$src:/src:ro" -v "$out:/out:rw" -w /work \
    "$SANDBOX_IMAGE" \
    sh -c 'cp -r /src/. /work/ && cd /work && crystal docs --format=json > /out/docs.json'
  rc=$?

  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  return $rc
}

# Upload the single generated artifact to <package>/<version>/docs.json in
# the docs bucket. One object per version, never a tree of files.
upload_docs() {
  local docs_json="$1" name="$2" version="$3"
  docker run --rm --network host \
    -v "$docs_json:/upload/docs.json:ro" --entrypoint sh "$MC_IMAGE" -c \
    "mc alias set local '$STORAGE_ENDPOINT' '$STORAGE_ACCESS_KEY' '$STORAGE_SECRET_KEY' >/dev/null && \
     mc cp /upload/docs.json 'local/$DOCS_BUCKET/$name/$version/docs.json'"
}

build_one() {
  local name="$1" repo="$2" requested_tag="$3"
  local workdir src outdir version resolved

  workdir="$(mktemp -d /tmp/real-docs.XXXXXX)"
  src="$workdir/src"
  outdir="$workdir/out"
  mkdir -p "$outdir" "$workdir/work"

  if resolved="$(resolve_tag "$repo" "$requested_tag")"; then
    version="${resolved#v}"
    if ! git clone --quiet --depth 1 --branch "$resolved" "$repo" "$src"; then
      echo "$name $requested_tag clone failed"
      rm -rf "$workdir"
      return 1
    fi
  else
    # The requested tag does not exist: fall back to the default branch and
    # record what was actually resolved as the version.
    if ! git clone --quiet --depth 1 "$repo" "$src"; then
      echo "$name $requested_tag clone failed"
      rm -rf "$workdir"
      return 1
    fi
    version="dev-$(git -C "$src" rev-parse --short HEAD)"
    echo "$name: tag $requested_tag not found, built default branch as $version"
  fi

  # Dependencies are needed for `crystal docs` to compile the shard, but many
  # shards still build docs without them, so a failure here is not fatal.
  # --skip-postinstall and --skip-executables keep this step code-free:
  # without them a dependency's postinstall hook would build and the
  # executable-link step would then abort the whole install halfway (that is
  # how amber lost its redis dependency and the docs build failed).
  if command -v shards >/dev/null 2>&1; then
    (cd "$src" && shards install --skip-postinstall --skip-executables --ignore-crystal-version) >/dev/null 2>&1 || \
      echo "$name: shards install failed, attempting docs build anyway"
  else
    echo "$name: shards not found on host, attempting docs build without dependencies"
  fi

  if ! sandboxed_crystal_docs "$src" "$outdir" "$workdir/work" "$workdir/timed-out" >"$workdir/docs.log" 2>&1; then
    if [ -f "$workdir/timed-out" ]; then
      echo "$name $version crystal docs exceeded the ${DOCS_SANDBOX_TIMEOUT_SECONDS}s wall clock limit, killed"
    else
      echo "$name $version crystal docs failed:"
      tail -n 5 "$workdir/docs.log" | sed 's/^/    /'
    fi
    rm -rf "$workdir"
    return 1
  fi

  # A zero-byte docs.json is a failed build: `crystal docs` can exit 0 having
  # written nothing useful.
  if [ ! -s "$outdir/docs.json" ]; then
    echo "$name $version crystal docs produced no docs.json"
    rm -rf "$workdir"
    return 1
  fi

  local json_bytes
  json_bytes="$(stat -f%z "$outdir/docs.json" 2>/dev/null || stat -c%s "$outdir/docs.json")"

  if ! upload_docs "$outdir/docs.json" "$name" "$version" >"$workdir/upload.log" 2>&1; then
    echo "$name $version upload to MinIO failed:"
    tail -n 5 "$workdir/upload.log" | sed 's/^/    /'
    rm -rf "$workdir"
    return 1
  fi

  rm -rf "$workdir"
  printf '%-14s %-12s %8s bytes  ok\n' "$name" "$version" "$json_bytes"
  return 0
}

main() {
  local specs=()

  if [ "$#" -eq 0 ]; then
    specs=("${DEFAULT_PACKAGES[@]}")
  elif [ "$#" -eq 3 ]; then
    specs=("$1 $2 $3")
  else
    echo "Usage: $0 [NAME REPO_URL TAG]" >&2
    exit 2
  fi

  command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 2; }
  command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 2; }

  local spec name repo tag
  for spec in "${specs[@]}"; do
    read -r name repo tag <<< "$spec"
    if build_one "$name" "$repo" "$tag"; then
      succeeded=$((succeeded + 1))
    else
      failed=$((failed + 1))
      failures+=("$name")
    fi
  done

  echo ""
  echo "Built $succeeded package(s), $failed failed."
  if [ "$failed" -gt 0 ]; then
    echo "Failed: ${failures[*]}"
  fi

  # Non-zero only when every package failed: a partial result still leaves
  # real documentation in the bucket.
  if [ "$succeeded" -eq 0 ]; then
    exit 1
  fi
}

main "$@"
