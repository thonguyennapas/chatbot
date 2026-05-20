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
    su postgres -c "\"/usr/lib/postgresql/$PG_VER/bin/createdb\" -p 5433 dify_plugin || true"
    su postgres -c "\"/usr/lib/postgresql/$PG_VER/bin/pg_ctl\" -D \"$PG_DATA\" stop"
else
    echo "Postgres data directory already initialized or initdb not found."
fi

# MySQL data init
MYSQL_DATA="$RUNTIME_ROOT/data/mysql"
if command -v mysqld >/dev/null 2>&1 && [ ! -d "$MYSQL_DATA" ]; then
    echo "Initializing MySQL data directory at $MYSQL_DATA"
    
    # 1. Temporarily disable AppArmor for mysqld so it can create the directory
    if command -v apparmor_parser >/dev/null 2>&1; then
        echo "Temporarily disabling AppArmor for mysqld..."
        mkdir -p /etc/apparmor.d/disable
        ln -sf /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/disable/
        apparmor_parser -R /etc/apparmor.d/usr.sbin.mysqld || true
    fi

    # 2. Run initialization (mysqld MUST create the directory itself, so we ensure it doesn't exist)
    rm -rf "$MYSQL_DATA"
    mysqld --initialize-insecure --user=root --datadir="$MYSQL_DATA"
    chown -R mysql:mysql "$MYSQL_DATA"

    # 3. Re-enable AppArmor and add an alias so it works during runtime
    if command -v apparmor_parser >/dev/null 2>&1; then
        echo "Re-enabling AppArmor with alias..."
        rm -f /etc/apparmor.d/disable/usr.sbin.mysqld
        if ! grep -q "$MYSQL_DATA" /etc/apparmor.d/tunables/alias; then
            echo "alias /var/lib/mysql/ -> $MYSQL_DATA/," >> /etc/apparmor.d/tunables/alias
        fi
        systemctl restart apparmor || true
    fi
else
    echo \"MySQL data directory already initialized or mysqld not found.\"
fi

# Create RAGFlow database in MySQL if not yet created
RAGFLOW_DB_MARKER="$RUNTIME_ROOT/.ragflow_db_created"
if command -v mysqld >/dev/null 2>&1 && [ -d "$MYSQL_DATA" ] && [ ! -f "$RAGFLOW_DB_MARKER" ]; then
    echo "Creating RAGFlow database (rag_flow) in MySQL..."
    
    # Start MySQL temporarily
    mysqld --datadir="$MYSQL_DATA" --port=3307 --user=mysql --socket=/tmp/ragflow_setup.sock &
    MYSQL_TMP_PID=$!
    sleep 5
    
    # Create database
    mysql --socket=/tmp/ragflow_setup.sock -u root -e "CREATE DATABASE IF NOT EXISTS rag_flow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || \
    mysql -h 127.0.0.1 -P 3307 -u root -e "CREATE DATABASE IF NOT EXISTS rag_flow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null || true
    
    # Stop MySQL
    kill "$MYSQL_TMP_PID" 2>/dev/null || true
    wait "$MYSQL_TMP_PID" 2>/dev/null || true
    rm -f /tmp/ragflow_setup.sock
    
    touch "$RAGFLOW_DB_MARKER"
    echo "  RAGFlow database created."
fi

echo "Database setup complete."
