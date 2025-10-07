# Build stage
FROM crystallang/crystal:1.17.1-alpine AS builder

# Build arg to choose which binary to build (api or worker)
ARG BUILD_TARGET=crystalshards

WORKDIR /app

# Copy dependency files
COPY shard.yml shard.lock ./

# Install dependencies
RUN shards install --production

# Copy source code
COPY . .

# Build the application based on BUILD_TARGET
# Note: Building without --release for much faster builds (~30s vs 5+ min)
# Production images should enable --release after initial testing
RUN if [ "$BUILD_TARGET" = "worker" ]; then \
      crystal build src/worker.cr --no-debug -o worker; \
    else \
      crystal build src/crystalshards.cr --no-debug; \
    fi

# Runtime stage
FROM alpine:latest

# Build arg to choose which binary to copy
ARG BUILD_TARGET=crystalshards

WORKDIR /app

# Install runtime dependencies for non-static builds
RUN apk add --no-cache \
    libgcc \
    libstdc++ \
    libc6-compat \
    pcre \
    gc \
    libevent \
    yaml \
    openssl

# Create non-root user (UID 1000 to match Kubernetes security context)
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    chown -R appuser:appuser /app

# Copy the compiled binary with proper ownership
COPY --from=builder --chown=1000:1000 /app/${BUILD_TARGET} .

# Ensure binary is executable
RUN chmod +x ./${BUILD_TARGET}

# Switch to non-root user
USER 1000

# Expose port (3000 for API, not used for worker)
EXPOSE 3000

# Run the appropriate binary
CMD if [ "$BUILD_TARGET" = "worker" ]; then \
      ./worker; \
    else \
      ./crystalshards; \
    fi
