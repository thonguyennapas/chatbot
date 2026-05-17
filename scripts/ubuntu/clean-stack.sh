#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/stack-common.sh"

REPO_ROOT=$(get_stack_repo_root)
RUNTIME_ROOT="$REPO_ROOT/runtime/ubuntu-stack"

echo "Cleaning data, logs, and temp files..."

rm -rf "$RUNTIME_ROOT/data/"*
rm -rf "$RUNTIME_ROOT/logs/"*
rm -rf "$RUNTIME_ROOT/tmp/"*
rm -rf "$RUNTIME_ROOT/pids/"*

echo "Cleaned."
