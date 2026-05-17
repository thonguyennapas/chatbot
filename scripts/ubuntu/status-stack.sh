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

printf "%-25s %-10s %-10s %s\n" "SERVICE" "STATUS" "PID" "PORT"
printf "%-25s %-10s %-10s %s\n" "-------" "------" "---" "----"

for (( i=0; i<$SERVICES_LENGTH; i++ )); do
    NAME=$(jq -r ".services[$i].name" "$CONFIG_FILE")
    PORT=$(jq -r ".services[$i].port" "$CONFIG_FILE")
    
    PID_FILE="$RUNTIME_ROOT/pids/$NAME.pid"
    STATUS="STOPPED"
    PID="-"
    
    if [ -f "$PID_FILE" ]; then
        READ_PID=$(cat "$PID_FILE")
        if kill -0 "$READ_PID" 2>/dev/null; then
            STATUS="RUNNING"
            PID="$READ_PID"
        else
            STATUS="STALE"
        fi
    fi
    
    PORT_STR="-"
    if [ "$PORT" -gt 0 ]; then
        if ss -tuln | grep -q ":$PORT "; then
            PORT_STR="$PORT (OPEN)"
        else
            PORT_STR="$PORT"
        fi
    fi
    
    printf "%-25s %-10s %-10s %s\n" "$NAME" "$STATUS" "$PID" "$PORT_STR"
done
