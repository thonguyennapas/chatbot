#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/stack-common.sh"

REPO_ROOT=$(get_stack_repo_root)
RUNTIME_ROOT="$REPO_ROOT/runtime/ubuntu-stack"
BIN_DIR="$RUNTIME_ROOT/bin"

mkdir -p "$BIN_DIR"

echo "Installing middleware. This requires sudo privileges for apt-get..."

# Update apt
sudo apt-get update

# Install Postgres, Redis, MySQL Server
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql redis-server mysql-server

# Qdrant
QDRANT_DIR="$BIN_DIR/qdrant"
if [ ! -f "$QDRANT_DIR/qdrant" ]; then
    echo "Downloading Qdrant..."
    mkdir -p "$QDRANT_DIR"
    wget -qO- https://github.com/qdrant/qdrant/releases/download/v1.12.5/qdrant-x86_64-unknown-linux-gnu.tar.gz | tar xz -C "$QDRANT_DIR"
fi

# MinIO
MINIO_DIR="$BIN_DIR/minio"
if [ ! -f "$MINIO_DIR/minio" ]; then
    echo "Downloading MinIO..."
    mkdir -p "$MINIO_DIR"
    wget -qO "$MINIO_DIR/minio" https://dl.min.io/server/minio/release/linux-amd64/minio
    chmod +x "$MINIO_DIR/minio"
fi

# Elasticsearch
ES_DIR="$BIN_DIR/elasticsearch"
if [ ! -d "$ES_DIR" ]; then
    echo "Downloading Elasticsearch 8.11.3..."
    wget -qO- https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-8.11.3-linux-x86_64.tar.gz | tar xz -C "$BIN_DIR"
    mv "$BIN_DIR/elasticsearch-8.11.3" "$ES_DIR"
fi

# Plugin Daemon
PLUGIN_DIR="$BIN_DIR/plugin-daemon"
if [ ! -f "$PLUGIN_DIR/plugin-daemon" ]; then
    echo "Downloading Dify Plugin Daemon..."
    mkdir -p "$PLUGIN_DIR"
    wget -qO "$PLUGIN_DIR/plugin-daemon" https://github.com/langgenius/dify-plugin-daemon/releases/download/0.6.1/dify-plugin-linux-amd64
    chmod +x "$PLUGIN_DIR/plugin-daemon"
fi

echo "Middleware installation complete."
