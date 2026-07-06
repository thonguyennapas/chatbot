#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/stack-common.sh"

echo "Verifying local network wiring..."

PORTS=(6379 5433 6333 5001 5002 3001 3000)
NAMES=("Redis" "PostgreSQL" "Qdrant" "Dify API" "Dify Plugin Daemon" "Dify Web" "Chatbot Frontend")

for i in "${!PORTS[@]}"; do
    PORT="${PORTS[$i]}"
    NAME="${NAMES[$i]}"
    
    if ss -tuln | grep -q ":$PORT "; then
        echo "[OK] $NAME is listening on $PORT"
    else
        echo "[FAIL] $NAME is NOT listening on $PORT"
    fi
done

echo "Wiring check complete."
