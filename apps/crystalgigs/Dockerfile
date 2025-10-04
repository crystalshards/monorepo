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
RUN crystal build src/crystalgigs.cr --release --static --no-debug

# Runtime stage
FROM alpine:latest

WORKDIR /app

# Copy the compiled binary
COPY --from=builder /app/crystalgigs .

# Expose port
EXPOSE 3000

# Run the app
CMD ["./crystalgigs"]
