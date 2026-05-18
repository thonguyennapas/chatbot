#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/stack-common.sh"

REPO_ROOT=$(get_stack_repo_root)
RUNTIME_ROOT="$REPO_ROOT/runtime/ubuntu-stack"

# Identify postgres path (default on Ubuntu is /usr/lib/postgresql/XX/bin/initdb)
PG_VER=$(ls /usr/lib/postgresql/ | sort -n | tail -1)
INITDB_CMD="/usr/lib/postgresql/$PG_VER/bin/initdb"
PG_DATA="$RUNTIME_ROOT/data/postgres"

if [ -x "$INITDB_CMD" ] && [ ! -d "$PG_DATA" ]; then
    echo "Initializing Postgres data directory at $PG_DATA"
    mkdir -p "$PG_DATA"
    chown -R postgres:postgres "$PG_DATA"
    
    # Ensure parent directories are traversable by the postgres user
    # This is required if the repository is cloned inside /root/
    DIR="$PG_DATA"
    while [ "$DIR" != "/" ]; do
        chmod o+x "$DIR"
        DIR=$(dirname "$DIR")
    done

    su postgres -c "$INITDB_CMD -D \"$PG_DATA\" --auth-host=trust --auth-local=trust"
    
    # Start it temporarily to create db
    echo "Creating dify database..."
    su postgres -c "\"/usr/lib/postgresql/$PG_VER/bin/pg_ctl\" -D \"$PG_DATA\" -o \"-p 5433\" start"
    sleep 3
    su postgres -c "\"/usr/lib/postgresql/$PG_VER/bin/createdb\" -p 5433 dify || true"
    su postgres -c "\"/usr/lib/postgresql/$PG_VER/bin/pg_ctl\" -D \"$PG_DATA\" stop"
else
    echo "Postgres data directory already initialized or initdb not found."
fi

# MySQL data init
MYSQL_DATA="$RUNTIME_ROOT/data/mysql"
if command -v mysqld >/dev/null 2>&1 && [ ! -d "$MYSQL_DATA" ]; then
    echo "Initializing MySQL data directory at $MYSQL_DATA"
    # Run as root so it can create the directory inside data/, avoiding permission denied.
    # Then change ownership to mysql so the actual service can run it later.
    rm -rf "$MYSQL_DATA"
    mysqld --initialize-insecure --user=root --datadir="$MYSQL_DATA"
    chown -R mysql:mysql "$MYSQL_DATA"
else
    echo "MySQL data directory already initialized or mysqld not found."
fi

echo "Database setup complete."
