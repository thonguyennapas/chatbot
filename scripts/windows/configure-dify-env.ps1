param(
    [string]$EnvFile        = 'runtime/dify/api/.env',
    [string]$ExampleFile    = 'runtime/dify/api/.env.example',
    [string]$VectorStore    = 'qdrant',
    [string]$QdrantUrl      = 'http://127.0.0.1:6333',
    [string]$QdrantApiKey   = '',
    [string]$DbHost         = '127.0.0.1',
    [int]   $DbPort         = 5432,
    [string]$DbUsername     = 'postgres',
    [string]$DbPassword     = '',
    [string]$DbDatabase     = 'dify',
    [string]$RedisHost      = '127.0.0.1',
    [int]   $RedisPort      = 6379,
    [string]$RedisPassword  = '',
    [string]$CelerySchema   = 'redis',
    [int]   $CeleryRedisDb  = 1,
    [switch]$NoBackup,
    [switch]$DryRun,
    [switch]$ShowDiff
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stack-common.ps1')

$repoRoot    = Get-StackRepoRoot
$envPath     = Resolve-StackPath -Path $EnvFile -RepoRoot $repoRoot
$examplePath = Resolve-StackPath -Path $ExampleFile -RepoRoot $repoRoot

# ── Build the key/value updates ───────────────────────────────────────────────
# Only these keys are touched. All other lines in .env are preserved verbatim.
$updates = [ordered]@{
    'VECTOR_STORE'       = $VectorStore
    'QDRANT_URL'         = $QdrantUrl
    'QDRANT_API_KEY'     = $QdrantApiKey
    'DB_HOST'            = $DbHost
    'DB_PORT'            = [string]$DbPort
    'DB_USERNAME'        = $DbUsername
    'DB_PASSWORD'        = $DbPassword
    'DB_DATABASE'        = $DbDatabase
    'REDIS_HOST'         = $RedisHost
    'REDIS_PORT'         = [string]$RedisPort
    'REDIS_PASSWORD'     = $RedisPassword
    'REDIS_USE_SSL'      = 'false'
    'CELERY_BROKER_URL'  = "$($CelerySchema)://$(if ($RedisPassword) { ":$RedisPassword@" } else { '' })$($RedisHost):$($RedisPort)/$CeleryRedisDb"
}

# Keys that should be commented out (Weaviate is replaced by Qdrant).
$commentKeys = @('WEAVIATE_ENDPOINT', 'WEAVIATE_API_KEY', 'WEAVIATE_GRPC_ENABLED', 'WEAVIATE_BATCH_SIZE')

# ── Load or seed the .env file ────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $envPath)) {
    if (-not (Test-Path -LiteralPath $examplePath)) {
        throw "Neither $envPath nor $examplePath exists. Clone Dify into runtime/dify first."
    }
    Write-Host "No .env found, seeding from $examplePath"
    if (-not $DryRun) {
        $envDir = Split-Path -Parent $envPath
        New-Item -ItemType Directory -Force -Path $envDir | Out-Null
        Copy-Item -LiteralPath $examplePath -Destination $envPath -Force
    }
}

$originalLines = if ($DryRun -and -not (Test-Path -LiteralPath $envPath)) {
    Get-Content -LiteralPath $examplePath
} else {
    Get-Content -LiteralPath $envPath
}

# ── Apply updates ─────────────────────────────────────────────────────────────
$matchedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$newLines = New-Object System.Collections.Generic.List[string]

foreach ($line in $originalLines) {
    $written = $false

    # Match KEY=value, with optional leading whitespace, and optional leading '#'
    if ($line -match '^\s*#?\s*([A-Z][A-Z0-9_]*)\s*=') {
        $key = $matches[1]

        if ($updates.Contains($key)) {
            $newValue = [string]$updates[$key]
            $newLines.Add("$key=$newValue") | Out-Null
            $null = $matchedKeys.Add($key)
            $written = $true
        }
        elseif ($commentKeys -contains $key) {
            if ($line -match '^\s*#') {
                $newLines.Add($line) | Out-Null
            } else {
                $newLines.Add("# replaced-by-qdrant: $line") | Out-Null
            }
            $written = $true
        }
    }

    if (-not $written) {
        $newLines.Add($line) | Out-Null
    }
}

# Append any update keys that did not appear in the file at all
$appended = @()
foreach ($key in $updates.Keys) {
    if (-not $matchedKeys.Contains($key)) {
        $appended += $key
        $newLines.Add("$key=$($updates[$key])") | Out-Null
    }
}

if ($appended.Count -gt 0) {
    $newLines.Insert($newLines.Count - $appended.Count, '') | Out-Null
    $newLines.Insert($newLines.Count - $appended.Count, '# Added by configure-dify-env.ps1') | Out-Null
}

# ── Show summary ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Configuration changes for: $envPath"
Write-Host "Updated in place:" ($matchedKeys -join ', ')
if ($appended.Count -gt 0) {
    Write-Host "Appended:" ($appended -join ', ')
}
$disabled = @()
foreach ($k in $commentKeys) {
    if ($originalLines | Where-Object { $_ -match "^\s*$k\s*=" }) { $disabled += $k }
}
if ($disabled.Count -gt 0) {
    Write-Host "Commented out:" ($disabled -join ', ')
}

if ($ShowDiff) {
    Write-Host ""
    Write-Host "--- diff ---"
    $oldSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$originalLines)
    $newSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$newLines)
    foreach ($l in $originalLines) {
        if (-not $newSet.Contains($l)) { Write-Host "-$l" -ForegroundColor Red }
    }
    foreach ($l in $newLines) {
        if (-not $oldSet.Contains($l)) { Write-Host "+$l" -ForegroundColor Green }
    }
}

# ── Write the file ────────────────────────────────────────────────────────────
if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN: no file changes. Re-run without -DryRun to apply."
    exit 0
}

if (-not $NoBackup -and (Test-Path -LiteralPath $envPath)) {
    $backupPath = "$envPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -LiteralPath $envPath -Destination $backupPath -Force
    Write-Host "Backup saved: $backupPath"
}

Set-Content -LiteralPath $envPath -Value $newLines -Encoding UTF8
Write-Host "Wrote: $envPath"
