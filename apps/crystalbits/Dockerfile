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
    pcre2 \
    gc \
    libevent \
    yaml \
    libxml2 \
    openssl \
    gmp

# Create non-root user (UID 1000 to match Kubernetes security context)
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser && \
    chown -R appuser:appuser /app

# Copy the compiled binary with proper ownership
COPY --from=builder --chown=1000:1000 /app/crystalbits .

# Ensure binary is executable
RUN chmod +x ./crystalbits

# Switch to non-root user
USER 1000

# Expose port
EXPOSE 3000

# Run the app
CMD ["./crystalbits"]
