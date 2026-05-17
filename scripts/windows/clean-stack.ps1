param(
    [string]$Config = '',
    [string[]]$Only = @(),
    [switch]$IncludeDisabled,
    [switch]$StopFirst,
    [switch]$Logs,
    [switch]$Cache,
    [switch]$Data,
    [switch]$ConfirmDataLoss
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stack-common.ps1')

$stack = Read-StackConfig -Config $Config
Initialize-StackRuntime -Stack $stack
$repoRoot = [string]$stack._repoRoot

if ($StopFirst) {
    & (Join-Path $PSScriptRoot 'stop-stack.ps1') -Config $stack._configPath -Only $Only -IncludeDisabled:$IncludeDisabled
}

if (-not $Logs -and -not $Cache -and -not $Data) {
    $Logs = $true
    $Cache = $true
}

$services = @(Get-StackServices -Stack $stack -Only $Only -IncludeDisabled:$IncludeDisabled)
foreach ($service in $services) {
    $pidPath = Get-ServicePidPath -Stack $stack -Service $service
    if (Test-Path -LiteralPath $pidPath) {
        Assert-PathInsideRepo -Path $pidPath -RepoRoot $repoRoot
        Remove-Item -LiteralPath $pidPath -Force
    }
}

if ($Logs -and $stack.clean -and $stack.clean.logGlobs) {
    foreach ($pattern in @($stack.clean.logGlobs)) {
        Remove-StackPathPattern -Pattern ([string]$pattern) -RepoRoot $repoRoot
    }
}

if ($Cache -and $stack.clean -and $stack.clean.cacheGlobs) {
    foreach ($pattern in @($stack.clean.cacheGlobs)) {
        Remove-StackPathPattern -Pattern ([string]$pattern) -RepoRoot $repoRoot
    }
}

if ($Data) {
    if (-not $ConfirmDataLoss) {
        throw 'Refusing to remove data paths without -ConfirmDataLoss.'
    }

    if ($stack.clean -and $stack.clean.dataGlobs) {
        foreach ($pattern in @($stack.clean.dataGlobs)) {
            Remove-StackPathPattern -Pattern ([string]$pattern) -RepoRoot $repoRoot
        }
    }
}

Write-Host 'Clean complete.'
