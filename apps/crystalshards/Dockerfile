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

# Build the server and the Lucky task runner.
#
# The task runner is a second binary and it is not optional: the crystalshards-migrate
# Cloud Run Job executes `./lucky db.migrate`, and the runtime stage below contains no
# Crystal toolchain and no lucky CLI. tasks.cr requires db/migrations/** at compile
# time, so the migrations are linked into this binary rather than read from disk.
#
# It is named `lucky`, not `tasks`, because `-o tasks` collides with the app's own
# tasks/ source directory: crystal writes nothing, the COPY below silently ships the
# directory instead of a binary, and the Job fails at exec with "is a directory".
#
# Built without --release for much faster builds. Enable --release once the
# Cloud Run cold start profile justifies the build time.
RUN crystal build src/crystalshards.cr --no-debug -o crystalshards && \
    crystal build tasks.cr --no-debug -o lucky

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
    gmp

# Create non-root user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    chown -R appuser:appuser /app

# Copy the compiled binaries with proper ownership
COPY --from=builder --chown=1000:1000 /app/crystalshards ./crystalshards
COPY --from=builder --chown=1000:1000 /app/lucky ./lucky

# Static assets. Lucky serves these from the relative path ./public at runtime
# (see Lucky::StaticFileHandler in src/app_server.cr), so omitting them makes every
# stylesheet and script 404 while the app itself looks healthy.
COPY --from=builder --chown=1000:1000 /app/public ./public

# Make both executable and prove each is a file rather than a directory. Shipping
# tasks/ in place of the task runner was a real defect here and it stayed invisible
# until the container tried to exec it.
RUN chmod +x ./crystalshards ./lucky && \
    test -x ./crystalshards && test ! -d ./crystalshards && \
    test -x ./lucky && test ! -d ./lucky

# Switch to non-root user
USER 1000

# Documentation only. Cloud Run injects PORT and config/server.cr binds to it.
EXPOSE 3000

# Exec form, so the server is PID 1 and receives Cloud Run's SIGTERM directly on
# scale-in. A shell form CMD leaves /bin/sh as PID 1, which does not forward signals,
# and the container is then killed rather than drained.
CMD ["./crystalshards"]
