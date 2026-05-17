param(
    [switch]$PostgreSQL,
    [switch]$MySQL,
    [switch]$MinIO,
    [switch]$Elasticsearch,
    [string]$ElasticsearchVersion = '8.11.3',
    [switch]$Qdrant,
    [string]$QdrantVersion = '1.9.2',
    [switch]$All,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stack-common.ps1')

$repoRoot = Get-StackRepoRoot
$binRoot = Join-Path $repoRoot 'runtime\windows-stack\bin'

if ($All) {
    $PostgreSQL = $true
    $MySQL      = $true
    $MinIO      = $true
    $Elasticsearch = $true
    $Qdrant     = $true
}

if (-not ($PostgreSQL -or $MySQL -or $MinIO -or $Elasticsearch -or $Qdrant)) {
    Write-Host 'No component selected. Use -All or individual flags: -PostgreSQL -MySQL -MinIO -Elasticsearch -Qdrant'
    Write-Host 'Add -DryRun to preview actions without downloading or installing.'
    exit 0
}

function Invoke-Winget {
    param([string]$Id, [string]$DisplayName)
    Write-Host ""
    Write-Host "=== $DisplayName (winget: $Id) ==="
    if ($DryRun) {
        Write-Host "DRY RUN: winget install --id $Id --silent --accept-package-agreements --accept-source-agreements"
        return
    }
    winget install --id $Id --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget exited $LASTEXITCODE - may already be installed or require reopen of terminal to update PATH."
    }
}

function Get-RemoteZip {
    param([string]$Url, [string]$Dest, [string]$DisplayName)
    Write-Host "Downloading $DisplayName..."
    if ($DryRun) {
        Write-Host "DRY RUN: Invoke-WebRequest $Url -> $Dest"
        return
    }
    Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
}

# ── PostgreSQL ────────────────────────────────────────────────────────────────
if ($PostgreSQL) {
    Invoke-Winget -Id 'PostgreSQL.PostgreSQL.17' -DisplayName 'PostgreSQL 17 (for Dify)'
    Write-Host "After install: initialise the data directory and create the dify database."
    Write-Host "  initdb -D runtime\windows-stack\data\postgres --encoding UTF8 --auth trust"
    Write-Host "  createdb -U postgres dify"
}

# ── MySQL ─────────────────────────────────────────────────────────────────────
if ($MySQL) {
    Invoke-Winget -Id 'Oracle.MySQL' -DisplayName 'MySQL 8.4 (for RAGFlow)'
    Write-Host "After install: create the rag_flow database and a dedicated user."
    Write-Host "  mysql -u root -p -e ""CREATE DATABASE rag_flow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"""
}

# ── MinIO ─────────────────────────────────────────────────────────────────────
if ($MinIO) {
    Invoke-Winget -Id 'MinIO.Server' -DisplayName 'MinIO Server (for RAGFlow)'
}

# ── Elasticsearch ─────────────────────────────────────────────────────────────
if ($Elasticsearch) {
    Write-Host ""
    Write-Host "=== Elasticsearch $ElasticsearchVersion (for RAGFlow) ==="

    $esUrl  = "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$ElasticsearchVersion-windows-x86_64.zip"
    $esDir  = Join-Path $binRoot 'elasticsearch'
    $tmpZip = Join-Path $binRoot "elasticsearch-$ElasticsearchVersion.zip"
    $tmpDir = Join-Path $binRoot '_es-extract-tmp'

    if ($DryRun) {
        Write-Host "DRY RUN: download $esUrl"
        Write-Host "DRY RUN: extract -> $esDir"
    } else {
        New-Item -ItemType Directory -Force -Path $binRoot | Out-Null
        Get-RemoteZip -Url $esUrl -Dest $tmpZip -DisplayName "Elasticsearch $ElasticsearchVersion"

        Write-Host "Extracting Elasticsearch..."
        New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
        Expand-Archive -LiteralPath $tmpZip -DestinationPath $tmpDir -Force
        Remove-Item -LiteralPath $tmpZip -Force

        $extracted = Get-ChildItem -Path $tmpDir -Directory -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $extracted) { throw "Elasticsearch zip extracted no directories." }

        if (Test-Path -LiteralPath $esDir) { Remove-Item -LiteralPath $esDir -Recurse -Force }
        Move-Item -LiteralPath $extracted.FullName -Destination $esDir
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

        Write-Host "Elasticsearch $ElasticsearchVersion installed to: $esDir"
    }

    Write-Host "Binary path used in stack config: runtime/windows-stack/bin/elasticsearch/bin/elasticsearch.bat"
}

# ── Qdrant ────────────────────────────────────────────────────────────────────
if ($Qdrant) {
    Write-Host ""
    Write-Host "=== Qdrant v$QdrantVersion (vector store for Dify, replaces Weaviate) ==="

    $qdrantUrl = "https://github.com/qdrant/qdrant/releases/download/v$QdrantVersion/qdrant-x86_64-pc-windows-msvc.zip"
    $qdrantDir = Join-Path $binRoot 'qdrant'
    $tmpZip    = Join-Path $binRoot "qdrant-$QdrantVersion.zip"

    if ($DryRun) {
        Write-Host "DRY RUN: download $qdrantUrl"
        Write-Host "DRY RUN: extract -> $qdrantDir"
    } else {
        New-Item -ItemType Directory -Force -Path $qdrantDir | Out-Null
        Get-RemoteZip -Url $qdrantUrl -Dest $tmpZip -DisplayName "Qdrant v$QdrantVersion"

        Write-Host "Extracting Qdrant..."
        Expand-Archive -LiteralPath $tmpZip -DestinationPath $qdrantDir -Force
        Remove-Item -LiteralPath $tmpZip -Force

        Write-Host "Qdrant v$QdrantVersion installed to: $qdrantDir"
        Write-Host "Storage data will be written to: runtime/windows-stack/data/storage"
    }

    Write-Host ""
    Write-Host "Dify api/.env changes needed:"
    Write-Host "  VECTOR_STORE=qdrant"
    Write-Host "  QDRANT_URL=http://127.0.0.1:6333"
    Write-Host "  (Remove or comment out any WEAVIATE_* lines)"
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Done ==="
Write-Host "Next steps:"
Write-Host "  1. Reopen this terminal (or run refreshenv) so winget-installed tools appear on PATH."
Write-Host "  2. scripts\windows\bootstrap.ps1   -- verify prerequisites"
Write-Host "  3. Edit runtime\windows-stack\stack.local.json -- set enabled:true for each service you installed"
Write-Host "  4. scripts\windows\start-stack.ps1 -- start enabled services"
