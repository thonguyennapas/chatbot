param(
    [string]$Config = '',
    [string[]]$Only = @(),
    [switch]$IncludeDisabled,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stack-common.ps1')

$stack = Read-StackConfig -Config $Config
$services = @(Get-StackServices -Stack $stack -Only $Only -IncludeDisabled:$IncludeDisabled)
$statuses = @()

foreach ($service in $services) {
    $statuses += Get-ServiceStatus -Stack $stack -Service $service
}

if ($AsJson) {
    $statuses | ConvertTo-Json -Depth 5
}
else {
    $statuses | Format-Table name, type, enabled, serviceStatus, pid, isRunning, port, isPortOpen, command -AutoSize
}
