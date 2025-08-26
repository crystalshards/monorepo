# Use the official Crystal image
FROM crystallang/crystal:1.10.1

# Install system dependencies
RUN apt-get update && \
    apt-get install -y curl libpq-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the working directory inside the container
WORKDIR /app

# Copy the shard files first for better caching
COPY shard.yml shard.lock ./

# Install Crystal dependencies
RUN shards install --production

# Copy the source code
COPY src/ ./src/

# Build the Crystal application
RUN shards build --production --release

# Expose the port the app runs on
EXPOSE 3000

# Set environment for production
ENV LUCKY_ENV=production

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

# Run the binary
CMD ["./bin/simple-lucky-registry"]