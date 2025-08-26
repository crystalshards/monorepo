FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install base dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    gnupg2 \
    libssl-dev \
    libreadline-dev \
    libyaml-dev \
    libxml2-dev \
    libxslt1-dev \
    libcurl4-openssl-dev \
    libffi-dev \
    libgdbm-dev \
    libncurses5-dev \
    libsqlite3-dev \
    libbz2-dev \
    zlib1g-dev \
    libevent-dev \
    libgmp-dev \
    libpcre2-dev \
    libpcre3-dev \
    postgresql-client \
    redis-tools \
    tmux \
    vim \
    htop \
    && rm -rf /var/lib/apt/lists/*

# Install mise (formerly rtx)
RUN curl https://mise.jdx.dev/install.sh | sh
ENV PATH="/root/.local/share/mise/shims:/root/.local/bin:${PATH}"
ENV MISE_TRUSTED_CONFIG_PATHS="/workspaces/monorepo"

# Set working directory
WORKDIR /workspaces/monorepo

# Ensure workspace directory exists
RUN mkdir -p /workspace/monorepo

# Set environment variables
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV WORKSPACE=/workspaces/monorepo

USER claude