param(
    [string]$Config = '',
    [string[]]$Only = @(),
    [switch]$IncludeDisabled,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stack-common.ps1')

$stack = Read-StackConfig -Config $Config
Initialize-StackRuntime -Stack $stack
$services = @(Get-StackServices -Stack $stack -Only $Only -IncludeDisabled:$IncludeDisabled)

foreach ($service in $services) {
    if (Test-ServiceUsesWindowsService -Service $service) {
        $serviceName = [string]$service.serviceName
        $windowsService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($null -eq $windowsService) {
            Write-Host "Windows service not found: $($service.name) service=$serviceName"
            continue
        }

        if ($windowsService.Status -eq 'Running') {
            Write-Host "Stopping Windows service: $($service.name) service=$serviceName"
            try {
                Stop-Service -Name $serviceName -Force:$Force -ErrorAction Stop
            }
            catch {
                throw "Unable to stop Windows service '$serviceName' for '$($service.name)'. Run PowerShell as Administrator or grant service control permissions. Original error: $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "Not running: $($service.name) service=$serviceName status=$($windowsService.Status)"
        }

        continue
    }

    $pidPath = Get-ServicePidPath -Stack $stack -Service $service
    $pidValue = Get-ManagedPid -Stack $stack -Service $service

    if ($null -eq $pidValue) {
        if (Test-Path -LiteralPath $pidPath) {
            Remove-Item -LiteralPath $pidPath -Force
        }
        Write-Host "Not running: $($service.name)"
        continue
    }

    if (Test-PidRunning -ProcessId $pidValue) {
        Write-Host "Stopping: $($service.name) pid=$pidValue"
        if ($Force) {
            Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
        }
        else {
            Stop-Process -Id $pidValue -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "Removing stale PID: $($service.name) pid=$pidValue"
    }

    if (Test-Path -LiteralPath $pidPath) {
        Remove-Item -LiteralPath $pidPath -Force
    }
}
