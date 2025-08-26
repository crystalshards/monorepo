FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install base dependencies
RUN apt-get -qq update && apt-get -qq install -y \
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

# Set working directory
WORKDIR /workspaces/monorepo

# Ensure workspace directory exists
RUN mkdir -p /workspaces/monorepo
RUN chown claude:claude /workspaces

# Set environment variables
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV WORKSPACE=/workspaces/monorepo

USER claude