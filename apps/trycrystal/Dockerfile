# Build stage
FROM crystallang/crystal:1.17.1-alpine AS builder

WORKDIR /app

# Copy dependency files
COPY shard.yml shard.lock ./

# Install dependencies
RUN shards install --production

# Copy source code
COPY . .

# Build the server. There is deliberately no second binary: this app has no
# database and no migrations, so there is no migrate entrypoint to build and
# no release phase to run. Adding a database later means adding that binary
# here, in ci.yml's build step, and a migration Job in terraform, all three.
#
# Built without --release for faster builds, matching the other apps in this
# monorepo. Enable --release once a cold start profile justifies the build
# time.
RUN crystal build src/trycrystal.cr --no-debug -o trycrystal

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

# Copy the compiled binary with proper ownership
COPY --from=builder --chown=1000:1000 /app/trycrystal ./trycrystal

# Static assets. Lucky serves these from the relative path ./public at runtime
# (see Lucky::StaticFileHandler in src/app_server.cr), so omitting them makes every
# stylesheet and script 404 while the app itself looks healthy.
COPY --from=builder --chown=1000:1000 /app/public ./public

# Make the binary executable and prove it is a file rather than a directory.
RUN chmod +x ./trycrystal && \
    test -x ./trycrystal && test ! -d ./trycrystal

# Switch to non-root user
USER 1000

# Documentation only. Cloud Run injects PORT and config/server.cr binds to it.
EXPOSE 3000

# Exec form, so the server is PID 1 and receives Cloud Run's SIGTERM directly on
# scale-in. A shell form CMD leaves /bin/sh as PID 1, which does not forward signals,
# and the container is then killed rather than drained.
CMD ["./trycrystal"]
