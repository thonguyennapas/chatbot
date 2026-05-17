param(
    [switch]$PostgreSQL,
    [switch]$MySQL,
    [switch]$All,
    [switch]$DryRun,
    [string]$PgUser     = 'postgres',
    [string]$PgDatabase = 'dify',
    [string]$MyRootPassword = '',
    [string]$MyDatabase = 'rag_flow'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stack-common.ps1')

$repoRoot    = Get-StackRepoRoot
$runtimeRoot = Join-Path $repoRoot 'runtime\windows-stack'
$dataRoot    = Join-Path $runtimeRoot 'data'
$logsRoot    = Join-Path $runtimeRoot 'logs'

if ($All) {
    $PostgreSQL = $true
    $MySQL      = $true
}

if (-not ($PostgreSQL -or $MySQL)) {
    Write-Host 'No database selected. Use -All or -PostgreSQL / -MySQL.'
    Write-Host 'Options:'
    Write-Host '  -PgUser postgres        (default: postgres)'
    Write-Host '  -PgDatabase dify        (default: dify)'
    Write-Host '  -MyRootPassword <pass>  (default: empty = insecure-init only)'
    Write-Host '  -MyDatabase rag_flow    (default: rag_flow)'
    exit 0
}

function Wait-Tcp {
    param([int]$Port, [int]$TimeoutSeconds = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort -Port $Port -TimeoutMilliseconds 300) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# ── PostgreSQL ────────────────────────────────────────────────────────────────
if ($PostgreSQL) {
    Write-Host ""
    Write-Host "=== PostgreSQL Setup ==="

    $pgData = Join-Path $dataRoot 'postgres'
    $pgLog  = Join-Path $logsRoot 'postgres-setup.out.log'

    if (Test-Path (Join-Path $pgData 'PG_VERSION')) {
        Write-Host "Data directory already initialised: $pgData"
        Write-Host "Skipping initdb. To re-initialise, delete $pgData first."
    } else {
        if ($DryRun) {
            Write-Host "DRY RUN: initdb -D $pgData --encoding UTF8 --auth trust --username $PgUser"
        } else {
            New-Item -ItemType Directory -Force -Path $pgData | Out-Null
            New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null
            Write-Host "Running initdb -> $pgData"
            $initResult = & initdb -D $pgData --encoding UTF8 --auth trust --username $PgUser 2>&1
            $initResult | Tee-Object -FilePath $pgLog
            if ($LASTEXITCODE -ne 0) { throw "initdb failed (exit $LASTEXITCODE). See $pgLog" }
            Write-Host "initdb complete."
        }
    }

    if ($DryRun) {
        Write-Host "DRY RUN: start postgres, createdb $PgDatabase, stop"
    } else {
        $pgCmd = Get-Command 'postgres' -ErrorAction SilentlyContinue
        if ($null -eq $pgCmd) { throw "'postgres' not on PATH. Run install-middleware.ps1 -PostgreSQL first." }
        $pgBin = [string]$pgCmd.Source
        Write-Host "Starting postgres temporarily on port 5433 (setup port)..."
        $pgSetupLog = Join-Path $logsRoot 'postgres-setup-tmp.log'
        $pgProc = Start-Process -FilePath $pgBin `
            -ArgumentList "-D `"$pgData`" -p 5433" `
            -RedirectStandardOutput $pgSetupLog `
            -RedirectStandardError $pgSetupLog `
            -PassThru -WindowStyle Hidden

        try {
            if (-not (Wait-Tcp -Port 5433 -TimeoutSeconds 30)) {
                throw "postgres did not open port 5433 within 30s. Check $pgSetupLog"
            }

            $env:PGPASSWORD = ''
            $existing = & psql -U $PgUser -p 5433 -tAc "SELECT 1 FROM pg_database WHERE datname='$PgDatabase'" postgres 2>&1
            if ($existing.Trim() -eq '1') {
                Write-Host "Database '$PgDatabase' already exists."
            } else {
                Write-Host "Creating database '$PgDatabase'..."
                & createdb -U $PgUser -p 5433 $PgDatabase
                if ($LASTEXITCODE -ne 0) { throw "createdb failed for '$PgDatabase'" }
                Write-Host "Database '$PgDatabase' created."
            }
        } finally {
            Write-Host "Stopping temporary postgres..."
            Stop-Process -Id $pgProc.Id -Force -ErrorAction SilentlyContinue
            $pgProc.WaitForExit(5000) | Out-Null
        }
    }

    Write-Host ""
    Write-Host "PostgreSQL setup done."
    Write-Host "Enable 'postgres' in stack.local.json and set start port to 5432 (remove -p 5433 override)."
    Write-Host "stack.local.json 'postgres' service uses: postgres -D runtime/windows-stack/data/postgres"
}

# ── MySQL ─────────────────────────────────────────────────────────────────────
if ($MySQL) {
    Write-Host ""
    Write-Host "=== MySQL Setup ==="

    $myData = Join-Path $dataRoot 'mysql'
    $myLog  = Join-Path $logsRoot 'mysql-setup.out.log'

    if (Test-Path (Join-Path $myData 'mysql')) {
        Write-Host "MySQL data directory already has system tables: $myData"
        Write-Host "Skipping --initialize. To re-initialise, delete $myData first."
    } elseif ($DryRun) {
        Write-Host "DRY RUN: mysqld --initialize-insecure --datadir=$myData"
    } else {
        $mysqldCmd = Get-Command 'mysqld' -ErrorAction SilentlyContinue
        if ($null -eq $mysqldCmd) { throw "'mysqld' not on PATH. Run install-middleware.ps1 -MySQL first." }
        $mysqldBin = [string]$mysqldCmd.Source

        New-Item -ItemType Directory -Force -Path $myData | Out-Null
        Write-Host "Initialising MySQL data directory (insecure root, no password)..."
        $initResult = & $mysqldBin --initialize-insecure --datadir=$myData --console 2>&1
        $initResult | Tee-Object -FilePath $myLog
        if ($LASTEXITCODE -ne 0) { throw "mysqld --initialize-insecure failed (exit $LASTEXITCODE). See $myLog" }
        Write-Host "MySQL initialised."
    }

    if ($DryRun) {
        Write-Host "DRY RUN: start mysqld, create database $MyDatabase, set root password, stop"
    } else {
        $mysqldCmd = Get-Command 'mysqld' -ErrorAction SilentlyContinue
        if ($null -eq $mysqldCmd) { throw "'mysqld' not on PATH. Run install-middleware.ps1 -MySQL first." }
        $mysqldBin = [string]$mysqldCmd.Source
        Write-Host "Starting mysqld temporarily on port 3307 (setup port)..."
        $mySetupLog = Join-Path $logsRoot 'mysql-setup-tmp.log'
        $myProc = Start-Process -FilePath $mysqldBin `
            -ArgumentList "--datadir=`"$myData`" --port=3307 --console --skip-grant-tables" `
            -RedirectStandardOutput $mySetupLog `
            -RedirectStandardError $mySetupLog `
            -PassThru -WindowStyle Hidden

        try {
            if (-not (Wait-Tcp -Port 3307 -TimeoutSeconds 60)) {
                throw "mysqld did not open port 3307 within 60s. Check $mySetupLog"
            }

            $mysqlCmd = Get-Command 'mysql' -ErrorAction SilentlyContinue
            if ($null -eq $mysqlCmd) { throw "'mysql' client not on PATH." }
            $mysqlBin = [string]$mysqlCmd.Source

            Write-Host "Creating database '$MyDatabase'..."
            & $mysqlBin -u root --port 3307 --protocol=TCP -e `
                "CREATE DATABASE IF NOT EXISTS $MyDatabase CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
            if ($LASTEXITCODE -ne 0) { throw "CREATE DATABASE '$MyDatabase' failed." }

            if (-not [string]::IsNullOrEmpty($MyRootPassword)) {
                Write-Host "Setting root@localhost password..."
                & $mysqlBin -u root --port 3307 --protocol=TCP -e `
                    "FLUSH PRIVILEGES; ALTER USER 'root'@'localhost' IDENTIFIED BY '$MyRootPassword'; FLUSH PRIVILEGES;"
                if ($LASTEXITCODE -ne 0) { Write-Warning "SET PASSWORD may have partially failed. Check manually." }
            } else {
                Write-Host "No -MyRootPassword given. Root has no password. Set one before enabling the service."
            }

        } finally {
            Write-Host "Stopping temporary mysqld..."
            Stop-Process -Id $myProc.Id -Force -ErrorAction SilentlyContinue
            $myProc.WaitForExit(10000) | Out-Null
        }
    }

    Write-Host ""
    Write-Host "MySQL setup done."
    Write-Host "Before enabling the 'mysql' service, update stack.local.json mysql arguments to:"
    Write-Host "  --datadir=runtime/windows-stack/data/mysql --port=3306 --console"
    Write-Host "Then update runtime/ragflow/conf/service_conf.yaml mysql password to match."
}

Write-Host ""
Write-Host "=== Database setup complete ==="
Write-Host "Next: enable services in runtime\windows-stack\stack.local.json and run start-stack.ps1"
