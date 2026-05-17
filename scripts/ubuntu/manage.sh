#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(dirname "$(dirname "$SCRIPT_DIR")")
RUNTIME_ROOT="$REPO_ROOT/runtime/ubuntu-stack"
STATE_FILE="$RUNTIME_ROOT/.install_state"

mkdir -p "$RUNTIME_ROOT"

print_usage() {
    echo "Usage: ./manage.sh [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  install      - Runs the entire setup pipeline end-to-end (Resumes from last failed step)."
    echo "  start        - Starts all services defined in stack.local.json."
    echo "  stop         - Gracefully stops all services."
    echo "  status       - Shows the running status of all services."
    echo "  nuke-ports   - Forcefully kills any processes holding project ports to free RAM."
    echo "  nuke-data    - Wipes all databases, logs, and resets the install state."
    echo ""
}

check_step() {
    local step="$1"
    if [ -f "$STATE_FILE" ] && grep -q "^${step}$" "$STATE_FILE"; then
        return 0 # True, step is done
    else
        return 1 # False
    fi
}

mark_step() {
    local step="$1"
    echo "$step" >> "$STATE_FILE"
}

cmd_install() {
    echo "=== Starting Installation Pipeline ==="
    
    if ! check_step "bootstrap"; then
        echo "--> Running bootstrap..."
        "$SCRIPT_DIR/bootstrap.sh"
        mark_step "bootstrap"
    else
        echo "--> Skipping bootstrap (Already done)"
    fi
    
    if ! check_step "middleware"; then
        echo "--> Running install-middleware..."
        "$SCRIPT_DIR/install-middleware.sh"
        mark_step "middleware"
    else
        echo "--> Skipping middleware (Already done)"
    fi
    
    if ! check_step "databases"; then
        echo "--> Running setup-databases..."
        "$SCRIPT_DIR/setup-databases.sh"
        mark_step "databases"
    else
        echo "--> Skipping databases (Already done)"
    fi
    
    if ! check_step "env"; then
        echo "--> Running configure-dify-env..."
        "$SCRIPT_DIR/configure-dify-env.sh"
        mark_step "env"
    else
        echo "--> Skipping env configuration (Already done)"
    fi
    
    echo "=== Installation complete! ==="
    echo "Run './manage.sh start' to launch the stack."
}

cmd_nuke_ports() {
    echo "Aggressively terminating processes on project ports..."
    # Ports: redis, pg, qdrant, dify-api, dify-plugin, dify-web, mysql, es, minio, rag-api, rag-web
    PORTS=(6379 5433 6333 5001 5002 3001 3307 1200 9000 9380 8080)
    
    for PORT in "${PORTS[@]}"; do
        if ss -tuln | grep -q ":$PORT "; then
            echo "Port $PORT is occupied. Nuking..."
            fuser -k -9 "$PORT/tcp" 2>/dev/null || true
        fi
    done
    echo "Ports nuked. RAM freed."
}

cmd_nuke_data() {
    echo "Nuking all data and logs..."
    "$SCRIPT_DIR/clean-stack.sh"
    echo "Removing installation state..."
    rm -f "$STATE_FILE"
    echo "Data completely nuked. Ready for a fresh install."
}

case "$1" in
    install)
        cmd_install
        ;;
    start)
        "$SCRIPT_DIR/start-stack.sh"
        ;;
    stop)
        "$SCRIPT_DIR/stop-stack.sh"
        ;;
    status)
        "$SCRIPT_DIR/status-stack.sh"
        ;;
    nuke-ports)
        cmd_nuke_ports
        ;;
    nuke-data)
        cmd_nuke_data
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
