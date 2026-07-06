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
    echo "  restart NAME - Restarts a single service by name (e.g. restart chatbot-frontend)."
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
    # Ports: redis, pg, qdrant, dify-api, dify-plugin, dify-web, chatbot-frontend
    PORTS=(6379 5433 6333 5001 5002 3001 3000)
    
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

cmd_restart() {
    local SERVICE_NAME="$1"
    if [ -z "$SERVICE_NAME" ]; then
        echo "Usage: ./manage.sh restart <service-name>"
        echo "Available services:"
        jq -r '.services[] | select(.enabled == true) | "  " + .name' "$RUNTIME_ROOT/stack.local.json" 2>/dev/null || echo "  (config not found)"
        exit 1
    fi

    local CONFIG_FILE="$RUNTIME_ROOT/stack.local.json"
    local PID_FILE="$RUNTIME_ROOT/pids/$SERVICE_NAME.pid"

    # Verify service exists in config
    local EXISTS=$(jq -r --arg name "$SERVICE_NAME" '.services[] | select(.name == $name) | .name' "$CONFIG_FILE" 2>/dev/null)
    if [ -z "$EXISTS" ]; then
        echo "Error: Service '$SERVICE_NAME' not found in stack.local.json"
        exit 1
    fi

    # Stop the service
    if [ -f "$PID_FILE" ]; then
        local OLD_PID=$(cat "$PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "Stopping: $SERVICE_NAME pid=$OLD_PID"
            kill "$OLD_PID" || true
            for (( w=0; w<10; w++ )); do
                if kill -0 "$OLD_PID" 2>/dev/null; then sleep 1; else break; fi
            done
            if kill -0 "$OLD_PID" 2>/dev/null; then
                echo "Force killing $SERVICE_NAME"
                kill -9 "$OLD_PID" || true
            fi
        fi
        rm -f "$PID_FILE"
    fi

    # Also kill by port if needed
    local PORT=$(jq -r --arg name "$SERVICE_NAME" '.services[] | select(.name == $name) | .port' "$CONFIG_FILE")
    if [ "$PORT" -gt 0 ] 2>/dev/null && ss -tuln | grep -q ":$PORT "; then
        echo "Freeing port $PORT..."
        fuser -k -9 "$PORT/tcp" 2>/dev/null || true
        sleep 1
    fi

    # Start the service (reuse start-stack logic for a single service)
    local IDX=$(jq -r --arg name "$SERVICE_NAME" '[.services[] | .name] | to_entries[] | select(.value == $name) | .key' "$CONFIG_FILE")
    local WD=$(jq -r ".services[$IDX].workingDirectory" "$CONFIG_FILE")
    local CMD=$(jq -r ".services[$IDX].command" "$CONFIG_FILE")
    local TIMEOUT=$(jq -r ".services[$IDX].startupTimeoutSeconds" "$CONFIG_FILE")
    local LOG_FILE="$RUNTIME_ROOT/logs/$SERVICE_NAME.out.log"
    local ERR_FILE="$RUNTIME_ROOT/logs/$SERVICE_NAME.err.log"

    mapfile -t ARGS < <(jq -r ".services[$IDX].arguments[]" "$CONFIG_FILE" 2>/dev/null || true)

    local TARGET_DIR="$REPO_ROOT"
    [ "$WD" != "." ] && TARGET_DIR="$REPO_ROOT/$WD"

    echo "Starting: $SERVICE_NAME"
    (
        cd "$TARGET_DIR"
        nohup "$CMD" "${ARGS[@]}" > "$LOG_FILE" 2> "$ERR_FILE" < /dev/null &
        echo $! > "$PID_FILE"
    )

    local NEW_PID=$(cat "$PID_FILE")
    echo "Started: $SERVICE_NAME pid=$NEW_PID"

    if [ "$PORT" -gt 0 ] 2>/dev/null; then
        source "$SCRIPT_DIR/stack-common.sh"
        if wait_for_port "$PORT" "$TIMEOUT" "$SERVICE_NAME"; then
            echo "  Port $PORT is open. ✓"
        else
            echo "  Failed: $SERVICE_NAME did not open port $PORT in $TIMEOUT seconds."
            if [ -f "$ERR_FILE" ] && [ -s "$ERR_FILE" ]; then
                echo "  --- Tail of $ERR_FILE ---"
                tail -n 10 "$ERR_FILE" | sed 's/^/    /'
                echo "  -------------------------"
            fi
        fi
    else
        echo "  Started (no port to check). ✓"
    fi
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
    restart)
        cmd_restart "$2"
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
