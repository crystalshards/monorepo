#!/bin/sh
# The untrusted half of a documentation build.
#
# This container compiles a third party shard. Crystal expands macros while
# compiling, and a macro can shell out, so everything below this line should be
# read as "code the shard author can influence runs here".
#
# That is why this holds no credentials. Its service account has zero IAM
# bindings, there is no key file, and the metadata server has nothing worth
# taking. It receives exactly three capabilities, all minted by the launcher
# and all expiring in minutes:
#
#   DOCS_SOURCE_URL      signed GET, one object, the prepared source tree
#   DOCS_UPLOAD_URL      signed PUT, one object, the single artifact
#   DOCS_LOG_UPLOAD_URL  signed PUT, one object, why a failed build failed
#
# It cannot choose where any of them land: the object keys are baked into the
# signatures. Widening this container's access, for any reason, removes the
# property the whole design exists for.
#
# THE RUN IS SPLIT IN THREE AND THE SPLIT IS THE POINT.
#
#   fetch    has the network. runs curl and tar. no shard code.
#   compile  runs `crystal docs`, which IS the shard's code. no network, ever.
#   upload   has the network. runs curl. no shard code. same process as fetch.
#
# Egress goes away at the boundary and never returns to anything descended from
# the compile. It is not a firewall rule and not a container flag: the compile
# is entered through no-egress, which installs a seccomp filter on itself and
# then execs. A seccomp filter is inherited by every descendant, survives
# execve, and has no removal interface at all, so the compile holds a
# restriction it has no way to lift. The filter is proven in-process on every
# run before the compiler starts, and a build whose confinement cannot be
# proven fails rather than running unconfined. sandbox/no-egress.c lists what
# an attacker would have to defeat.
#
# The upload runs in this process, which predates the compile and has never
# executed a line of shard code. That is the one place the phases are not
# literally sequential in privilege, and it is deliberate. The alternative is
# a bucket mount, which means giving this Job's identity real IAM on the
# bucket, and a filesystem path into our storage is far worse than a signature
# over one object key. Cloud Run has no non-network handoff to put in its
# place: task level networking is shared by every container in the task, so a
# sidecar uploader would sit on exactly the same network this one does.
#
# What protects it is that the compile cannot reach this process usefully. The
# supervisor stays root while every process influenced by the source runs as
# uid 1000, so the compile cannot read /proc/1/environ or /proc/1/mem. It is
# execed through `env -i` with only a fixed PATH, its private HOME, the source
# directory, and optional non-secret compiler inputs. The signed URLs never
# cross that boundary, and no-egress refuses to start if a DOCS_ variable does.
# ptrace and process_vm_readv are denied as well, and every binary on PATH is
# root owned, so nothing the compile can write is anything we later run. The
# only thing it hands back is bytes on a descriptor opened before it started,
# addressed to a key it cannot choose and validated by the launcher before
# anything is published.
#
# The signatures are bounded too, as defense in depth around that process
# boundary. Each names one object, one method, and expires in minutes.
# Everything they address is this build's own scratch: its source going in,
# its artifact and log coming out, all under a per-build prefix the bucket
# lifecycle rule collects. They are not a path to the bucket, another build,
# or any Google API, because this identity holds no IAM at all.
#
# The link-local metadata server matters as much as the internet. It is not
# reached over a VPC and no egress setting covers it, so a control that blocks
# public addresses and leaves 169.254.169.254 alone is the shape of the hole
# rather than the fix. Denying the socket denies both, along with AF_VSOCK,
# which on a microVM host is a path to the hypervisor.
#
# Kept as a shell script rather than a compiled binary of ours deliberately.
# The less of our code that shares a process with an untrusted compile, the
# smaller the thing anyone has to reason about.
set -eu

# Fixed, so a compile cannot arrange for the upload that follows it to find a
# different curl. Nothing on this PATH is writable by the build's uid.
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

: "${DOCS_SOURCE_URL:?DOCS_SOURCE_URL is not set; the launcher must mint a signed GET for the source}"
: "${DOCS_UPLOAD_URL:?DOCS_UPLOAD_URL is not set; the launcher must mint a signed PUT for the artifact}"
: "${DOCS_UPLOAD_CONTENT_TYPE:?DOCS_UPLOAD_CONTENT_TYPE is not set; it must match what the PUT url was signed for}"

# The third signed PUT, and it is required rather than optional. The launcher
# cannot see inside this execution: Cloud Run reports that a task failed, not
# why. Without somewhere to put the reason, a maintainer whose macro fetches at
# compile time is told only that the build produced no output, which sends them
# looking for a compiler version problem they do not have. Making it optional
# would mean the one failure mode this change introduces is also the one the
# reader cannot be told about.
: "${DOCS_LOG_UPLOAD_URL:?DOCS_LOG_UPLOAD_URL is not set; the launcher must mint a signed PUT for the build diagnostic}"
DOCS_LOG_CONTENT_TYPE="${DOCS_LOG_CONTENT_TYPE:-text/plain}"

# Exit codes. The launcher reads the diagnostic rather than these, but a local
# run and the containment spec both assert on them, so they are stable.
EXIT_SHARD_FAILED=1         # the shard did not compile
EXIT_SHARD_WANTED_NETWORK=2 # ... and it failed running a command at compile time
EXIT_SANDBOX_UNPROVEN=3     # the confinement could not be established
EXIT_TRANSPORT=4            # a signed url did not work

# A docs.json larger than this is not documentation, and the artifact is
# produced by untrusted code, so the upload is bounded here rather than
# discovered to be unbounded in the bucket.
MAX_ARTIFACT_BYTES=67108864

# The compiler excerpt carried back to the reader. DocsBuildStatus caps
# last_error at 4000 characters and keeps the FRONT, so this has to leave room
# for the explanation that goes above it. Anything longer is still in this
# container's log, which is where an operator looks.
MAX_COMPILER_EXCERPT_BYTES=2800

# How much of the compiler's output reaches this container's own log. Bounds
# a hostile shard emitting gigabytes of diagnostics; an operator who needs
# more than this has a shard that is not going to document anyway.
MAX_COMPILER_LOG_BYTES=1048576

# The account everything the shard can influence runs as. This script stays
# root so that /proc/1/environ, which holds the three signed urls for the
# whole build, belongs to a user the compile is not.
BUILD_USER=1000:1000

WORK_DIR="$(mktemp -d)"
SOURCE_DIR="$WORK_DIR/src"
COMPILE_HOME="$WORK_DIR/home"
DOCS_JSON="$WORK_DIR/docs.json"
COMPILER_LOG="$WORK_DIR/compiler.log"

# What the launcher is allowed to learn about a failure, in the order a reader
# needs it: our explanation first, the compiler's own words after. It never
# carries a signed url. curl's errors go to this container's stderr and stop
# there, and the compile that fills COMPILER_LOG has no capability-bearing
# variable to leak and runs under a parent it cannot read.
DIAGNOSTIC="$WORK_DIR/diagnostic.txt"

# Set once the compile has exited, to a file created after it exited. Until
# then there is no compiler output and nothing safe to name.
COMPILER_COPY=""

mkdir -p "$SOURCE_DIR" "$COMPILE_HOME"
: >"$DOCS_JSON"
: >"$COMPILER_LOG"
: >"$DIAGNOSTIC"

# The compile needs to reach its two directories and write in them, and needs
# to reach nothing else. Traversable, so it can cd into the source; not
# writable, so it cannot replace this script's files with symlinks on its way
# out. The files themselves stay root owned and readable, which is fine: they
# hold compiler output, never a url.
chmod 0755 "$WORK_DIR"
chown "$BUILD_USER" "$SOURCE_DIR" "$COMPILE_HOME"

# Descriptors opened BEFORE any shard code exists, so what this script later
# reads and writes is the file it created. The files and their parent are root
# owned today, which already prevents the compile replacing their paths; the
# descriptors keep that guarantee true if a future permissions edit widens
# access by mistake. A descriptor is an inode, not a path, and never follows a
# symlink left behind by a macro.
exec 4<"$DOCS_JSON"
exec 5<"$COMPILER_LOG"
exec 6>>"$DIAGNOSTIC"
exec 7<"$DIAGNOSTIC"

note() {
  printf '%s\n' "$*" >&6
  printf '%s\n' "$*" >&2
}

# Composed here rather than accumulated in place, so the file curl is handed
# is one created at this moment, from descriptors, with the explanation ahead
# of the compiler excerpt. DocsBuildStatus keeps the front of this text, so
# the order is the difference between a reader seeing why the build failed and
# a reader seeing 4000 characters of type errors.
upload_diagnostic() {
  final="$(mktemp)"
  cat <&7 >"$final" || :

  if [ -n "$COMPILER_COPY" ] && [ -s "$COMPILER_COPY" ]; then
    printf '\ncrystal docs said:\n\n' >>"$final"
    head -c "$MAX_COMPILER_EXCERPT_BYTES" "$COMPILER_COPY" >>"$final" || :
  fi

  curl --fail --silent --show-error --max-time 60 \
    -X PUT \
    -H "Content-Type: ${DOCS_LOG_CONTENT_TYPE}" \
    --upload-file "$final" \
    "$DOCS_LOG_UPLOAD_URL" >/dev/null 2>&1 ||
    echo "docs-build: could not upload the diagnostic" >&2
}

give_up() {
  code="$1"
  shift
  note "docs-build: $*"
  upload_diagnostic
  exit "$code"
}

cd "$WORK_DIR"

# ---------------------------------------------------------------- fetch ----
# This phase is the positive control for the one that follows it. Asserting
# that the compile cannot reach the network proves nothing unless the same
# probe, on the same machine, in the same run, reports the network reachable
# here. Without this line the containment check passes just as happily when
# the probe is broken, when the binary is missing, or when the host simply has
# no network.
echo "docs-build: fetch phase, the network is expected to work here" >&2
if ! egress-probe --expect-open; then
  give_up "$EXIT_TRANSPORT" \
    "no route off this machine even in the fetch phase, so the source cannot be collected. This container needs egress to reach its signed urls."
fi

echo "docs-build: fetching source" >&2
# --fail so an expired or wrong signature stops here rather than producing an
# error page that tar would then try to unpack.
if ! curl --fail --silent --show-error --location --max-time 300 \
  -o "$WORK_DIR/source.tar.gz" "$DOCS_SOURCE_URL"; then
  give_up "$EXIT_TRANSPORT" "could not download the prepared source tree"
fi

# Unpacked as the build user, not as root. The tarball was built from a
# repository a stranger wrote, and tar running as root restores ownership,
# permissions and device nodes from whatever the archive claims. It gets no
# network and no environment either: tar parses hostile bytes, so it is the
# other process in this container that should not be holding a signed url
# while it works.
#
# `env -i` goes OUTSIDE no-egress, not inside, and the order is the whole
# point. env runs as root, so nothing unprivileged ever sees the urls, and
# no-egress is created by execve with a clean environment, so the region
# /proc/<pid>/environ reports never held them. Clearing inside no-egress
# instead would leave them readable there: clearenv edits libc's table on the
# heap and the kernel keeps reporting the strings recorded at exec.
env -i PATH="$PATH" \
  no-egress --user "$BUILD_USER" tar -xzf "$WORK_DIR/source.tar.gz" -C "$SOURCE_DIR"
rm -f "$WORK_DIR/source.tar.gz"

# -------------------------------------------------------------- compile ----
# Past this point the shard's own code runs.
#
# A fresh allowlisted environment and a HOME of its own. Nothing from the
# supervisor is inherited, and the compiler's cache does not need its scratch.
#
# --format=json emits one document on stdout instead of writing an HTML tree.
# That single file is the entire artifact: documentation is rendered by our own
# site, and shard-authored HTML served from our origin would be stored XSS.
echo "docs-build: compile phase, egress is removed before the compiler starts" >&2

# The external half of the negative control, and it runs in its own process so
# its output goes to this container's log rather than into the compiler log.
# That separation is what lets the classifier below treat the filter's errno
# appearing in the compiler log as evidence the SHARD reached for a socket;
# if our own probe wrote that string there, it would be there on every build.
#
# The compile process is not taking this run's word for it either: no-egress
# proves the filter in-process, after installing it and before exec, on the
# invocation below as well as this one.
set +e
env -i PATH="$PATH" no-egress --user "$BUILD_USER" egress-probe --expect-closed
probe_status=$?
set -e

if [ "$probe_status" -ne 0 ]; then
  give_up "$EXIT_SANDBOX_UNPROVEN" \
    "the compile phase could still reach the network, so the build was stopped before any shard code ran. This is a fault in the build platform, not in the shard."
fi

# The launcher names optional compile inputs DOCS_* because they are container
# overrides. Rename them at this boundary: no DOCS_* name enters the confined
# process, so no-egress can keep treating that prefix as a leaked capability.
set +e
env -i \
  PATH="$PATH" \
  HOME="$COMPILE_HOME" \
  TERM=dumb \
  SOURCE_DIR="$SOURCE_DIR" \
  CORE_CRYSTAL_PATH="${DOCS_CRYSTAL_PATH:-}" \
  ENTRY_FILE="${DOCS_ENTRY_FILE:-}" \
  PROJECT_NAME="${DOCS_PROJECT_NAME:-}" \
  PROJECT_VERSION="${DOCS_PROJECT_VERSION:-}" \
  no-egress --user "$BUILD_USER" /bin/sh -c '
    cd "$SOURCE_DIR" || exit 61

    set -- docs --format=json
    if [ -n "$CORE_CRYSTAL_PATH" ]; then
      export CRYSTAL_PATH="$CORE_CRYSTAL_PATH"
    fi
    if [ -n "$PROJECT_NAME" ]; then
      set -- "$@" "--project-name=$PROJECT_NAME"
    fi
    if [ -n "$PROJECT_VERSION" ]; then
      set -- "$@" "--project-version=$PROJECT_VERSION"
    fi
    if [ -n "$ENTRY_FILE" ]; then
      set -- "$@" "$ENTRY_FILE"
    fi

    crystal "$@" || exit 62
  ' >"$DOCS_JSON" 2>>"$COMPILER_LOG"
compile_status=$?
set -e

# The shard's code is finished. Its output is drained once, through the
# descriptor opened before it started, into a file created now. Reopening
# "$COMPILER_LOG" by name here would undo the whole point of that descriptor:
# a macro could have left a symlink at that path on its way out, and this is
# the text we are about to print and publish.
COMPILER_COPY="$(mktemp)"
head -c "$MAX_COMPILER_LOG_BYTES" <&5 >"$COMPILER_COPY" || :
exec 5<&-
cat "$COMPILER_COPY" >&2 || :

case "$compile_status" in
0) ;;
61)
  give_up "$EXIT_SHARD_FAILED" "the prepared source tree had nothing to compile"
  ;;
7[0-4])
  give_up "$EXIT_SANDBOX_UNPROVEN" \
    "the compile phase could not be confined, so no shard code was run. This is a fault in the build platform, not in the shard."
  ;;
*)
  # Two different claims, kept apart on purpose, because only one of them is
  # evidence.
  #
  # EAFNOSUPPORT is the errno this sandbox's filter returns, and curl's 6 and
  # 7 are "could not resolve" and "could not connect". Nothing in a
  # documentation build produces any of them for another reason, so finding
  # one in the compiler's output means something in this compile genuinely
  # reached for the network. That is worth saying outright. Our own probe
  # deliberately runs in a separate process so it cannot put the errno here.
  #
  # A failed macro command on its own is weaker: the command may have wanted
  # the network, or it may have been broken for its own reasons. Guessing
  # would put a confident wrong explanation on someone's documentation page,
  # so that branch names what the compiler reported and offers the policy as
  # context rather than as a diagnosis.
  #
  # A shard can of course print any of these strings on purpose and mislabel
  # its own failure page. That costs it its own documentation and nothing
  # else, which is not worth defending against.
  if grep -q 'Address family not supported by protocol' "$COMPILER_COPY" ||
    grep -q 'curl: (6)' "$COMPILER_COPY" ||
    grep -q 'curl: (7)' "$COMPILER_COPY"; then
    note "docs-build: this shard tried to use the network while it was being compiled, and"
    note "docs-build: the attempt was refused."
    note "docs-build:"
    note "docs-build: Compiling a shard runs its macros, so a documentation build that is"
    note "docs-build: allowed to make requests is a build any published shard can use to reach"
    note "docs-build: our infrastructure. Documentation is therefore compiled with no network"
    note "docs-build: access at all: no outbound connection, no name resolution, no metadata"
    note "docs-build: server. Refusing this is deliberate, and it will not be turned off."
    note "docs-build:"
    note "docs-build: A macro that reads from the network at compile time has to stop doing"
    note "docs-build: that, or tolerate the request failing."
    give_up "$EXIT_SHARD_WANTED_NETWORK" "the shard reached for the network while compiling"
  fi

  if grep -q 'error executing command:' "$COMPILER_COPY" ||
    grep -q 'Error executing run:' "$COMPILER_COPY"; then
    note "docs-build: this shard did not compile. The compiler reports that a command run by"
    note "docs-build: one of its macros failed."
    note "docs-build:"
    note "docs-build: If that command reads from the network, that is why: documentation is"
    note "docs-build: compiled with no network access, because compiling a shard runs its"
    note "docs-build: macros and a build allowed to make requests is a build any published"
    note "docs-build: shard can use to reach our infrastructure. The command named below is"
    note "docs-build: the one to remove or to guard so that it tolerates failing."
    give_up "$EXIT_SHARD_FAILED" "a command run by a macro failed during compilation"
  fi

  give_up "$EXIT_SHARD_FAILED" "crystal docs exited $compile_status"
  ;;
esac

# --------------------------------------------------------------- upload ----
# Back in the parent, which still has the network and never ran a line of the
# shard's code. The bytes come off the descriptor opened before the
# compile started, so they are the bytes the compiler wrote, whatever the path
# points at now.
#
# One byte over the cap is read deliberately: a document that would have been
# truncated is reported as too large rather than uploaded as JSON that stops
# in the middle of a string and reads to the launcher as a broken compiler.
ARTIFACT="$(mktemp)"
head -c "$((MAX_ARTIFACT_BYTES + 1))" <&4 >"$ARTIFACT"
exec 4<&-

if [ "$(wc -c <"$ARTIFACT")" -gt "$MAX_ARTIFACT_BYTES" ]; then
  give_up "$EXIT_SHARD_FAILED" \
    "the generated documentation is larger than $MAX_ARTIFACT_BYTES bytes, which is bigger than any real shard's api documentation, so it was not published"
fi

# An empty document is a failed build even when the compiler exited 0. Failing
# here means the launcher sees a failed execution rather than publishing
# nothing over something.
if [ ! -s "$ARTIFACT" ]; then
  give_up "$EXIT_SHARD_FAILED" "crystal docs produced no output"
fi

echo "docs-build: uploading documentation" >&2
# The content type must be byte-identical to the one the URL was signed for.
# GCS signs the content type, so a mismatch is a 403 that reads like a broken
# build. It is passed in rather than hardcoded so it cannot drift.
if ! curl --fail --silent --show-error --max-time 300 \
  -X PUT \
  -H "Content-Type: ${DOCS_UPLOAD_CONTENT_TYPE}" \
  --upload-file "$ARTIFACT" \
  "$DOCS_UPLOAD_URL"; then
  give_up "$EXIT_TRANSPORT" "could not upload the documentation artifact"
fi

echo "docs-build: done" >&2
