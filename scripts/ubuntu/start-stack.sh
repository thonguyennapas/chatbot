#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/stack-common.sh"

REPO_ROOT=$(get_stack_repo_root)
RUNTIME_ROOT="$REPO_ROOT/runtime/ubuntu-stack"
CONFIG_FILE="$RUNTIME_ROOT/stack.local.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config not found at $CONFIG_FILE. Run bootstrap.sh first."
    exit 1
fi

SERVICES_LENGTH=$(jq '.services | length' "$CONFIG_FILE")

echo "Starting services..."

for (( i=0; i<$SERVICES_LENGTH; i++ )); do
    ENABLED=$(jq -r ".services[$i].enabled" "$CONFIG_FILE")
    NAME=$(jq -r ".services[$i].name" "$CONFIG_FILE")
    
    if [ "$ENABLED" != "true" ]; then
        continue
    fi
    
    PID_FILE="$RUNTIME_ROOT/pids/$NAME.pid"
    LOG_FILE="$RUNTIME_ROOT/logs/$NAME.out.log"
    ERR_FILE="$RUNTIME_ROOT/logs/$NAME.err.log"
    
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "Already running: $NAME pid=$OLD_PID"
            continue
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    echo "Starting: $NAME"
    
    WD=$(jq -r ".services[$i].workingDirectory" "$CONFIG_FILE")
    CMD=$(jq -r ".services[$i].command" "$CONFIG_FILE")
    PORT=$(jq -r ".services[$i].port" "$CONFIG_FILE")
    TIMEOUT=$(jq -r ".services[$i].startupTimeoutSeconds" "$CONFIG_FILE")
    
    # Extract arguments as a bash array
    mapfile -t ARGS < <(jq -r ".services[$i].arguments[]" "$CONFIG_FILE" 2>/dev/null || true)
    
    # Resolve working directory relative to repo root
    if [ "$WD" = "." ]; then
        TARGET_DIR="$REPO_ROOT"
    else
        TARGET_DIR="$REPO_ROOT/$WD"
    fi
    
    # Launch process
    (
        cd "$TARGET_DIR"
        nohup "$CMD" "${ARGS[@]}" > "$LOG_FILE" 2> "$ERR_FILE" < /dev/null &
        echo $! > "$PID_FILE"
    )
    
    NEW_PID=$(cat "$PID_FILE")
    echo "Started: $NAME pid=$NEW_PID"
    
    if [ "$PORT" -gt 0 ]; then
        if wait_for_port "$PORT" "$TIMEOUT" "$NAME"; then
            echo "  Port $PORT is open."
        else
            echo "  Failed: Service $NAME did not open port $PORT in $TIMEOUT seconds."
            if [ -f "$ERR_FILE" ] && [ -s "$ERR_FILE" ]; then
                echo "  --- Tail of $ERR_FILE ---"
                tail -n 10 "$ERR_FILE" | sed 's/^/    /'
                echo "  -------------------------"
            elif [ -f "$LOG_FILE" ] && [ -s "$LOG_FILE" ]; then
                echo "  --- Tail of $LOG_FILE (stderr was empty) ---"
                tail -n 10 "$LOG_FILE" | sed 's/^/    /'
                echo "  -------------------------"
            fi
            kill "$NEW_PID" 2>/dev/null || true
            exit 1
        fi
    fi
done

echo "Stack startup complete."
