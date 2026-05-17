param(
    [switch]$OverwriteConfig,
    [switch]$PrerequisitesJson,
    [switch]$InstallNodeTools,
    [switch]$InstallPythonTools
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stack-common.ps1')

$repoRoot = Get-StackRepoRoot
$runtimeRoot = Join-Path $repoRoot 'runtime\windows-stack'
$exampleConfig = Join-Path $repoRoot 'scripts\windows\stack.example.json'
$localConfig = Join-Path $runtimeRoot 'stack.local.json'

foreach ($child in @($runtimeRoot, (Join-Path $runtimeRoot 'logs'), (Join-Path $runtimeRoot 'pids'), (Join-Path $runtimeRoot 'tmp'), (Join-Path $runtimeRoot 'data'))) {
    New-Item -ItemType Directory -Force -Path $child | Out-Null
}

if ($OverwriteConfig -or -not (Test-Path -LiteralPath $localConfig)) {
    Copy-Item -LiteralPath $exampleConfig -Destination $localConfig -Force
    if (-not $PrerequisitesJson) {
        Write-Host "Wrote config: $localConfig"
    }
}
else {
    if (-not $PrerequisitesJson) {
        Write-Host "Config already exists: $localConfig"
    }
}

$stack = Read-StackConfig -Config $localConfig

function Get-PrerequisiteRows {
    param([Parameter(Mandatory = $true)]$Stack)

    $rows = @()
    foreach ($prereq in @($Stack.prerequisites)) {
        $commands = @($prereq.commands)
        $missing = @()
        $found = @()
        foreach ($command in $commands) {
            $resolved = Find-StackCommand -Command ([string]$command)
            if ($null -eq $resolved) {
                $missing += [string]$command
            }
            else {
                $found += [pscustomobject]@{
                    name = [string]$command
                    source = [string]$resolved
                }
            }
        }

        $rows += [pscustomobject]@{
            name = [string]$prereq.name
            commands = $commands
            missing = $missing
            found = $found
            isAvailable = ($missing.Count -eq 0)
        }
    }

    return $rows
}

if ($InstallNodeTools) {
    $corepack = Get-Command 'corepack.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $corepack) {
        throw 'corepack.cmd is required to activate pnpm, but it was not found on PATH.'
    }

    Write-Host 'Activating pnpm 10.33.2 with Corepack...'
    & $corepack.Source prepare pnpm@10.33.2 --activate
    if ($LASTEXITCODE -ne 0) {
        throw "corepack prepare pnpm@10.33.2 failed with exit code $LASTEXITCODE"
    }
}

if ($InstallPythonTools) {
    $python = Get-Command 'python' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $python) {
        throw 'python is required to install uv, but it was not found on PATH.'
    }

    Write-Host 'Installing uv with pip --user...'
    & $python.Source -m pip install --user uv
    if ($LASTEXITCODE -ne 0) {
        throw "python -m pip install --user uv failed with exit code $LASTEXITCODE"
    }
}

$prereqRows = @(Get-PrerequisiteRows -Stack $stack)

if ($PrerequisitesJson) {
    $prereqRows | ConvertTo-Json -Depth 6
    exit 0
}

Write-Host ''
Write-Host 'Prerequisites:'
foreach ($row in $prereqRows) {
    if ($row.isAvailable) {
        Write-Host "  OK      $($row.name)"
    }
    else {
        Write-Host "  MISSING $($row.name): $($row.missing -join ', ')"
    }
}

Write-Host ''
Write-Host 'Next commands:'
Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\status-stack.ps1 -IncludeDisabled'
Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\start-stack.ps1'
Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\stop-stack.ps1 -IncludeDisabled'
