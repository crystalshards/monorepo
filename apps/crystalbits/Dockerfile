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
RUN crystal build src/crystalbits.cr --no-debug

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

# Copy the compiled binary
COPY --from=builder /app/crystalbits .

# Expose port
EXPOSE 3000

# Run the app
CMD ["./crystalbits"]
