FROM crystallang/crystal:1.17.1-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    yaml-dev \
    libxml2-dev \
    openssl-dev \
    git

# Set working directory
WORKDIR /app

# Copy shard files
COPY shard.yml shard.lock* ./

# Install dependencies
RUN shards install --production

# Copy source code
COPY src/ src/

# Build the application
RUN shards build --production --release --no-debug

FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    gc-dev \
    pcre-dev \
    libevent-dev \
    openssl-dev \
    git

# Create app user
RUN addgroup -g 1001 -S crystal && \
    adduser -u 1001 -S crystal -G crystal

# Set working directory
WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/bin/crystalworker /app/crystalworker

# Change ownership
RUN chown -R crystal:crystal /app

# Switch to app user
USER crystal

# Start the application
CMD ["./crystalworker"]