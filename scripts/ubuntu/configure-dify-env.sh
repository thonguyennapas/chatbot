#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/stack-common.sh"

REPO_ROOT=$(get_stack_repo_root)

# Configure Dify API env
API_ENV="$REPO_ROOT/runtime/dify/api/.env"
API_EXAMPLE="$REPO_ROOT/runtime/dify/api/.env.example"

if [ ! -f "$API_ENV" ] && [ -f "$API_EXAMPLE" ]; then
    echo "Creating api/.env"
    cp "$API_EXAMPLE" "$API_ENV"
    
    # Use sed to update VECTOR_STORE
    sed -i 's/^VECTOR_STORE=.*/VECTOR_STORE=qdrant/' "$API_ENV"
    echo "QDRANT_URL=http://127.0.0.1:6333" >> "$API_ENV"
    
    # DB settings
    sed -i 's/^DB_HOST=.*/DB_HOST=127.0.0.1/' "$API_ENV"
    sed -i 's/^DB_PORT=.*/DB_PORT=5433/' "$API_ENV"
    
    # Plugin Daemon settings
    sed -i 's/^PLUGIN_DAEMON_URL=.*/PLUGIN_DAEMON_URL=http:\/\/127.0.0.1:5002/' "$API_ENV"
fi

# Configure Dify Web env
WEB_ENV="$REPO_ROOT/runtime/dify/web/.env.local"
WEB_EXAMPLE="$REPO_ROOT/runtime/dify/web/.env.example"

if [ ! -f "$WEB_ENV" ] && [ -f "$WEB_EXAMPLE" ]; then
    echo "Creating web/.env.local"
    cp "$WEB_EXAMPLE" "$WEB_ENV"
    
    sed -i 's/^NEXT_PUBLIC_API_PREFIX=.*/NEXT_PUBLIC_API_PREFIX=http:\/\/127.0.0.1:5001\/console\/api/' "$WEB_ENV"
    sed -i 's/^NEXT_PUBLIC_PUBLIC_API_PREFIX=.*/NEXT_PUBLIC_PUBLIC_API_PREFIX=http:\/\/127.0.0.1:5001\/api/' "$WEB_ENV"
fi

# Configure Chatbot Frontend env
FRONTEND_ENV="$REPO_ROOT/frontend/.env.local"
FRONTEND_EXAMPLE="$REPO_ROOT/frontend/.env.local.example"

if [ ! -f "$FRONTEND_ENV" ] && [ -f "$FRONTEND_EXAMPLE" ]; then
    echo "Creating frontend/.env.local"
    cp "$FRONTEND_EXAMPLE" "$FRONTEND_ENV"
    
    # Generate a random 32-byte base64 string for SESSION_SECRET
    RANDOM_SECRET=$(openssl rand -base64 32)
    # Use | as delimiter for sed to avoid issues with / or + in base64
    sed -i "s|^SESSION_SECRET=.*|SESSION_SECRET=${RANDOM_SECRET}|" "$FRONTEND_ENV"
fi

echo "Environment configuration complete."
