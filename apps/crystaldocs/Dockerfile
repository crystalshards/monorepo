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
# Note: Removed --static flag as it's not needed in containers and significantly slows down builds
RUN crystal build src/crystaldocs.cr --release --no-debug

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
COPY --from=builder /app/crystaldocs .

# Expose port
EXPOSE 3000

# Run the app
CMD ["./crystaldocs"]
