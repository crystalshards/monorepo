# Minimal Dockerfile for Crystal Shards Registry (stdlib only)
FROM crystallang/crystal:1.17.0-alpine AS builder

# Install build dependencies
RUN apk add --no-cache --update \
  yaml-static \
  openssl-dev \
  openssl-libs-static \
  pcre-dev \
  libevent-dev \
  libevent-static

WORKDIR /app

# Copy shard files
COPY shard.yml ./

# No external dependencies to install since we're using stdlib only
RUN crystal deps || echo "No dependencies to install"

# Copy source code
COPY src/ ./src/

# Build the application
RUN crystal build --release --static --no-debug src/simple-registry.cr -o simple-registry

# Runtime stage - minimal Alpine image
FROM alpine:3.20

# Install minimal runtime dependencies
RUN apk add --no-cache ca-certificates wget

WORKDIR /app

# Copy the built binary
COPY --from=builder /app/simple-registry .

# Create non-root user
RUN adduser -D -s /bin/sh crystal && \
    chown crystal:crystal simple-registry
USER crystal

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Run the application
CMD ["./simple-registry"]