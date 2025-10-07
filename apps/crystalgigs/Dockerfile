# Build stage
FROM crystallang/crystal:1.17.1-alpine AS builder

WORKDIR /app

# Copy dependency files
COPY shard.yml shard.lock ./

# Install dependencies
RUN shards install --production

# Copy source code
COPY . .

# Build the application
# Note: Building without --release for much faster builds (~30s vs 5+ min)
# Production images should enable --release after initial testing
RUN crystal build src/crystalgigs.cr --no-debug

# Runtime stage
FROM alpine:latest

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

# Copy the compiled binary
COPY --from=builder /app/crystalgigs .

# Ensure binary is executable
RUN chmod +x ./crystalgigs

# Switch to non-root user
USER 1000

# Expose port
EXPOSE 3000

# Run the app
CMD ["./crystalgigs"]
