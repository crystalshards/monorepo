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
RUN if [ "$BUILD_TARGET" = "worker" ]; then \
      crystal build src/worker.cr --release --static --no-debug -o worker; \
    else \
      crystal build src/crystalshards.cr --release --static --no-debug; \
    fi

# Runtime stage
FROM alpine:latest

# Build arg to choose which binary to copy
ARG BUILD_TARGET=crystalshards

WORKDIR /app

# Copy the compiled binary
RUN if [ "$BUILD_TARGET" = "worker" ]; then \
      echo "worker" > /app/.build_target; \
    else \
      echo "crystalshards" > /app/.build_target; \
    fi

COPY --from=builder /app/${BUILD_TARGET} .

# Expose port (3000 for API, not used for worker)
EXPOSE 3000

# Run the appropriate binary
CMD if [ "$BUILD_TARGET" = "worker" ]; then \
      ./worker; \
    else \
      ./crystalshards; \
    fi
