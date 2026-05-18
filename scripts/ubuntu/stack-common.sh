#!/bin/bash
set -e

# Core Stack Configuration functions for Ubuntu

get_stack_repo_root() {
    # Resolve the directory of the script and go two levels up (scripts/ubuntu/ -> repo root)
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")
    dirname "$(dirname "$script_dir")"
}

read_stack_config() {
    local config_file="$1"
    if [ ! -f "$config_file" ]; then
        echo "Error: Config file not found at $config_file" >&2
        exit 1
    fi
    cat "$config_file"
}

find_stack_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        command -v "$cmd"
    else
        echo ""
    fi
}

wait_for_port() {
    local port="$1"
    local timeout="$2"
    local service_name="$3"
    
    local start_time
    start_time=$(date +%s)
    
    while true; do
        if ss -tuln | grep -q ":$port "; then
            return 0
        fi
        
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Error: Service '$service_name' did not open port $port within $timeout seconds." >&2
            return 1
        fi
        
        sleep 1
    done
}
