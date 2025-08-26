FROM crystallang/crystal:1.10.1-alpine AS builder

# Install dependencies
RUN apk add --no-cache \
    postgresql-dev \
    yaml-dev \
    libevent-dev

# Create app directory
WORKDIR /app

# Copy dependency files
COPY shard.yml shard.lock ./

# Install dependencies
RUN shards install --production

# Copy source code
COPY src/ ./src/

# Build the application
RUN crystal build --release --no-debug src/admin.cr -o admin

# Production image
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache \
    postgresql-libs \
    libevent \
    ca-certificates \
    tzdata

# Create non-root user
RUN addgroup -g 1000 crystal && \
    adduser -D -u 1000 -G crystal crystal

# Create app directory
WORKDIR /app

# Copy compiled binary
COPY --from=builder /app/admin /app/admin

# Change ownership
RUN chown -R crystal:crystal /app

# Switch to non-root user
USER crystal

# Expose port
EXPOSE 4000

# Set health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:4000/health || exit 1

# Start the application
CMD ["./admin"]