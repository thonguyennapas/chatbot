#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/stack-common.sh"

REPO_ROOT=$(get_stack_repo_root)
RUNTIME_ROOT="$REPO_ROOT/runtime/ubuntu-stack"
EXAMPLE_CONFIG="$SCRIPT_DIR/stack.example.json"
LOCAL_CONFIG="$RUNTIME_ROOT/stack.local.json"

# Parse arguments
OVERWRITE_CONFIG=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --overwrite-config) OVERWRITE_CONFIG=true ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Create necessary directories
mkdir -p "$RUNTIME_ROOT/logs" "$RUNTIME_ROOT/pids" "$RUNTIME_ROOT/tmp" "$RUNTIME_ROOT/data"

if [ "$OVERWRITE_CONFIG" = true ] || [ ! -f "$LOCAL_CONFIG" ]; then
    cp "$EXAMPLE_CONFIG" "$LOCAL_CONFIG"
    echo "Wrote config: $LOCAL_CONFIG"
else
    echo "Config already exists: $LOCAL_CONFIG"
fi

# Check Prerequisites using jq
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed. Please run: sudo apt-get install jq"
    exit 1
fi

echo ""
echo "Prerequisites Check:"
MISSING_PREREQS=false

# We parse the prerequisites list from the JSON
PREREQS_LENGTH=$(jq '.prerequisites | length' "$LOCAL_CONFIG")
for (( i=0; i<$PREREQS_LENGTH; i++ )); do
    NAME=$(jq -r ".prerequisites[$i].name" "$LOCAL_CONFIG")
    COMMANDS=$(jq -r ".prerequisites[$i].commands[]" "$LOCAL_CONFIG")
    
    MISSING_CMDS=()
    for CMD in $COMMANDS; do
        if [ -z "$(find_stack_command "$CMD")" ]; then
            MISSING_CMDS+=("$CMD")
        fi
    done
    
    if [ ${#MISSING_CMDS[@]} -eq 0 ]; then
        echo "  OK      $NAME"
    else
        echo "  MISSING $NAME: ${MISSING_CMDS[*]}"
        MISSING_PREREQS=true
    fi
done

echo ""
if [ "$MISSING_PREREQS" = true ]; then
    echo "Some prerequisites are missing. Please install them or adjust your PATH."
else
    echo "All prerequisites met."
fi

echo ""
echo "Next commands:"
echo "  ./scripts/ubuntu/status-stack.sh"
echo "  ./scripts/ubuntu/start-stack.sh"
echo "  ./scripts/ubuntu/stop-stack.sh"
