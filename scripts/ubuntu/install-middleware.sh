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

# Install Postgres, Redis (v3.3: no MySQL needed)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql redis-server

# Qdrant
QDRANT_DIR="$BIN_DIR/qdrant"
if [ ! -f "$QDRANT_DIR/qdrant" ]; then
    echo "Downloading Qdrant..."
    mkdir -p "$QDRANT_DIR"
    wget -qO- https://github.com/qdrant/qdrant/releases/download/v1.12.5/qdrant-x86_64-unknown-linux-gnu.tar.gz | tar xz -C "$QDRANT_DIR"
fi

# Plugin Daemon (must be built from source — the GitHub release binary is the CLI, not the server)
PLUGIN_DIR="$BIN_DIR/plugin-daemon"
PLUGIN_SRC_DIR="$RUNTIME_ROOT/src/dify-plugin-daemon"
PLUGIN_VERSION="0.6.1"

if [ ! -f "$PLUGIN_DIR/plugin-daemon-server" ]; then
    echo "Building Dify Plugin Daemon from source (v${PLUGIN_VERSION})..."
    mkdir -p "$PLUGIN_DIR"

    # Ensure Go is installed
    if ! command -v go >/dev/null 2>&1; then
        echo "Error: Go is required to build the plugin daemon. Install it with: sudo apt-get install golang-go"
        exit 1
    fi

    # Clone or update source
    if [ ! -d "$PLUGIN_SRC_DIR" ]; then
        git clone --depth 1 --branch "$PLUGIN_VERSION" https://github.com/langgenius/dify-plugin-daemon.git "$PLUGIN_SRC_DIR"
    fi

    # Build server binary (the actual daemon)
    echo "  Building server binary..."
    (cd "$PLUGIN_SRC_DIR" && go build \
        -ldflags "-X 'github.com/langgenius/dify-plugin-daemon/pkg/manifest.VersionX=${PLUGIN_VERSION}'" \
        -o "$PLUGIN_DIR/plugin-daemon-server" cmd/server/main.go)

    # Build commandline binary (for migrations)
    echo "  Building commandline binary..."
    (cd "$PLUGIN_SRC_DIR" && go build \
        -ldflags "-X 'main.VersionX=${PLUGIN_VERSION}'" \
        -o "$PLUGIN_DIR/plugin-daemon-cli" ./cmd/commandline/)

    echo "  Plugin Daemon binaries built successfully."
fi

echo "Middleware installation complete."
