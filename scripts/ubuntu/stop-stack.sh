#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/stack-common.sh"

REPO_ROOT=$(get_stack_repo_root)
RUNTIME_ROOT="$REPO_ROOT/runtime/ubuntu-stack"

# Read all PID files and kill them in reverse order (to stop apps before databases)
PID_FILES=($(ls "$RUNTIME_ROOT/pids/"*.pid 2>/dev/null || true))

if [ ${#PID_FILES[@]} -eq 0 ]; then
    echo "No processes to stop."
    exit 0
fi

# Reverse the array
for (( i=${#PID_FILES[@]}-1 ; i>=0 ; i-- )) ; do
    PID_FILE="${PID_FILES[i]}"
    NAME=$(basename "$PID_FILE" .pid)
    PID=$(cat "$PID_FILE")
    
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping: $NAME pid=$PID"
        kill "$PID" || true
        
        # Wait up to 10 seconds for it to die
        for (( w=0; w<10; w++ )); do
            if kill -0 "$PID" 2>/dev/null; then
                sleep 1
            else
                break
            fi
        done
        
        # Force kill if still alive
        if kill -0 "$PID" 2>/dev/null; then
            echo "Force killing $NAME pid=$PID"
            kill -9 "$PID" || true
        fi
    else
        echo "Removing stale PID: $NAME pid=$PID"
    fi
    
    rm -f "$PID_FILE"
done

echo "Stack stopped."
