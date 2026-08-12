# Build stage
FROM crystallang/crystal:1.17.1-alpine AS builder

WORKDIR /app

# Copy dependency files
COPY shard.yml shard.lock ./

# Install dependencies
RUN shards install --production

# Apply Avram nilability fix
RUN apk add --no-cache patch
COPY patches/avram-nilable-fix.patch /tmp/
RUN cd lib/avram && patch -p1 < /tmp/avram-nilable-fix.patch

# Copy source code
COPY . .

# Build the server, the migration entrypoint, the discovery sweep entrypoint and the
# documentation status reconciliation entrypoint.
#
# The extra three are separate binaries and none is optional: the crystalshards-migrate
# Cloud Run Job runs `./migrate`, the discover-shards Job runs `./discover-shards`, a
# one-off Job execution runs `./reconcile-docs-status`, and this runtime stage carries
# no Crystal toolchain and no lucky CLI. src/migrate.cr
# requires db/migrations/** at compile time, so the migrations are linked into the
# binary rather than read from disk, and it requires only the database config, so the
# Job needs only DATABASE_URL. src/discover_shards.cr requires the models, queries and
# operations discovery writes through plus the crawlers, and likewise nothing from
# config/server.cr, so that Job also needs only DATABASE_URL. Its host tokens are all
# optional: a host without one is skipped by name and the run still succeeds.
# src/reconcile_docs_status.cr reads the docs database and lists the docs bucket, so it
# needs DOCS_DATABASE_URL and DOCS_BUCKET alongside DATABASE_URL, and nothing else.
#
# Deliberately not tasks.cr for any of them: that loads the entire app, every config/ file
# runs at load time, and each one raises without its own production variable. It also
# cannot be named `-o tasks`, which silently collides with the app's own tasks/
# directory and ships a directory where a binary should be.
#
# Built without --release for much faster builds. Enable --release once the
# Cloud Run cold start profile justifies the build time.
RUN crystal build src/crystalshards.cr --no-debug -o crystalshards && \
    crystal build src/migrate.cr --no-debug -o migrate && \
    crystal build src/discover_shards.cr --no-debug -o discover-shards && \
    crystal build src/reconcile_docs_status.cr --no-debug -o reconcile-docs-status

# Prove each artifact is an executable file before it is ever copied into the runtime
# stage.
#
# `crystal build -o NAME` writes a binary INTO NAME when a directory called NAME
# already exists, reports success, and leaves the container to die on
# `exec: is a directory` at start time. That is not hypothetical here: it is what
# `-o tasks` did against the app's tasks/ directory. Checking in the builder means a
# name that collides with a directory fails the build rather than the deploy.
RUN for binary in crystalshards migrate discover-shards reconcile-docs-status; do \
      test -f "$binary" || { echo "$binary is not a file"; exit 1; }; \
      test ! -d "$binary" || { echo "$binary is a directory, not a binary"; exit 1; }; \
      test -x "$binary" || { echo "$binary is not executable"; exit 1; }; \
    done

# Runtime stage
#
# Pinned to the Alpine release the builder image ships (crystallang/crystal:1.17.1-alpine
# is Alpine 3.20.7). The binaries are dynamically linked, so a floating alpine:latest can
# drift ahead of the musl and library sonames they were built against and fail at exec
# time rather than at build time.
FROM alpine:3.20

WORKDIR /app

# Install runtime dependencies for non-static builds
RUN apk add --no-cache \
    libgcc \
    libstdc++ \
    libc6-compat \
    pcre2 \
    gc \
    libevent \
    yaml \
    libxml2 \
    openssl \
    gmp \
    git

# git and shards are not optional extras here: this image also runs
# docs-launcher, and its fetch phase shells out to both. `git clone`,
# `git checkout` and `git rev-parse` fix the revision being documented, then
# `shards install` populates lib/ before the tree is handed to the sandbox that
# compiles it. Without them the launcher raises File::NotFoundError on 'git'
# the moment a build starts, which is exactly what production did on the first
# dispatch that ever got past authentication.
#
# The fetch deliberately runs HERE rather than in the sandbox. `shards install`
# resolves URLs out of a shard.yml the shard author wrote, so it is egress an
# attacker chooses; it belongs in the process that runs no untrusted code, not
# in the container that then compiles it.
#
# shards is copied from the builder rather than installed from apk, because the
# apk package pulls the entire compiler in to get one binary. It is the same
# shards the application was built with, and it is dynamically linked against
# the libraries already listed above.
#
# No compiler is copied with it. Shards only wants `crystal` to learn the
# compiler version, and that is supplied to it directly, by the sandbox that
# knows which compiler will actually do the compiling.
COPY --from=builder /usr/bin/shards /usr/bin/shards

# Prove both actually run here, rather than discovering at the first dispatch
# that one of them is missing or cannot resolve a library. This whole class of
# failure was invisible until a task reached the launcher, so it is asserted at
# build time where it costs a red build instead of a stuck queue.
RUN git --version && shards --version

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    chown -R appuser:appuser /app

# Copy the compiled binaries with proper ownership. One image serves the web service
# and every Job; which binary runs is the Job's command, not a separate build.
COPY --from=builder --chown=1000:1000 /app/crystalshards ./crystalshards
COPY --from=builder --chown=1000:1000 /app/migrate ./migrate
COPY --from=builder --chown=1000:1000 /app/discover-shards ./discover-shards
COPY --from=builder --chown=1000:1000 /app/reconcile-docs-status ./reconcile-docs-status

# Static assets. Lucky serves these from the relative path ./public at runtime
# (see Lucky::StaticFileHandler in src/app_server.cr), so omitting them makes every
# stylesheet and script 404 while the app itself looks healthy.
COPY --from=builder --chown=1000:1000 /app/public ./public

# Make them executable and prove each really is an executable file rather than a
# directory. Shipping tasks/ in place of the task runner was a real defect here and it
# stayed invisible until the container tried to exec it, so this is asserted on both
# sides: in the builder where the artifact is produced, and here where a COPY of a
# directory would otherwise arrive silently and only fail at `docker run`.
RUN chmod +x ./crystalshards ./migrate ./discover-shards ./reconcile-docs-status && \
    for binary in ./crystalshards ./migrate ./discover-shards ./reconcile-docs-status; do \
      test -f "$binary" || { echo "$binary is not a file"; exit 1; }; \
      test ! -d "$binary" || { echo "$binary is a directory, not a binary"; exit 1; }; \
      test -x "$binary" || { echo "$binary is not executable"; exit 1; }; \
    done

# Switch to non-root user
USER 1000

# Documentation only. Cloud Run injects PORT and config/server.cr binds to it.
EXPOSE 3000

# Exec form, so the server is PID 1 and receives Cloud Run's SIGTERM directly on
# scale-in. A shell form CMD leaves /bin/sh as PID 1, which does not forward signals,
# and the container is then killed rather than drained.
CMD ["./crystalshards"]
