param(
    [string]$Config = '',
    [string[]]$Only = @(),
    [switch]$IncludeDisabled,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'stack-common.ps1')

$stack = Read-StackConfig -Config $Config
Initialize-StackRuntime -Stack $stack
$services = @(Get-StackServices -Stack $stack -Only $Only -IncludeDisabled:$IncludeDisabled)

if ($services.Count -eq 0) {
    Write-Host 'No services selected.'
    exit 0
}

foreach ($service in $services) {
    $status = Get-ServiceStatus -Stack $stack -Service $service
    if ($status.isRunning) {
        Write-Host "Already running: $($service.name) pid=$($status.pid)"
        continue
    }

    if (Test-ServiceUsesWindowsService -Service $service) {
        $serviceName = [string]$service.serviceName
        if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
            throw "Windows service for '$($service.name)' not found: $serviceName"
        }

        if ($DryRun) {
            Write-Host "DRY RUN: Start-Service $serviceName"
            continue
        }

        Write-Host "Starting Windows service: $($service.name) service=$serviceName"
        try {
            Start-Service -Name $serviceName -ErrorAction Stop
        }
        catch {
            throw "Unable to start Windows service '$serviceName' for '$($service.name)'. Run PowerShell as Administrator or grant service control permissions. Original error: $($_.Exception.Message)"
        }

        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline) {
            $current = Get-Service -Name $serviceName
            if ($current.Status -eq 'Running') {
                break
            }
            Start-Sleep -Milliseconds 500
        }

        if ($null -ne $service.PSObject.Properties['port'] -and $service.port) {
            $timeout = 30
            if ($null -ne $service.PSObject.Properties['startupTimeoutSeconds'] -and $service.startupTimeoutSeconds) {
                $timeout = [int]$service.startupTimeoutSeconds
            }
            $null = Wait-ServicePort -Name ([string]$service.name) -Port ([int]$service.port) -TimeoutSeconds $timeout
        }

        Write-Host "Started Windows service: $($service.name)"
        continue
    }

    $commandPath = Resolve-ServiceCommand -Stack $stack -Service $service
    $workingDirectory = Resolve-StackPath -Path ([string]$service.workingDirectory) -RepoRoot ([string]$stack._repoRoot)
    if (-not (Test-Path -LiteralPath $workingDirectory)) {
        throw "Working directory for service '$($service.name)' not found: $workingDirectory"
    }

    $logPaths = Get-ServiceLogPaths -Stack $stack -Service $service
    $arguments = @()
    if ($null -ne $service.PSObject.Properties['arguments']) {
        $arguments = @($service.arguments)
    }
    $argumentString = ConvertTo-ArgumentString -Arguments $arguments

    if ($DryRun) {
        Write-Host "DRY RUN: $($service.name): $commandPath $argumentString"
        continue
    }

    Write-Host "Starting: $($service.name)"
    $process = Start-Process `
        -FilePath $commandPath `
        -ArgumentList $argumentString `
        -WorkingDirectory $workingDirectory `
        -RedirectStandardOutput $logPaths.stdout `
        -RedirectStandardError $logPaths.stderr `
        -WindowStyle Hidden `
        -PassThru

    $pidPath = Get-ServicePidPath -Stack $stack -Service $service
    Set-Content -LiteralPath $pidPath -Value ([string]$process.Id) -Encoding ASCII

    $timeout = 30
    if ($null -ne $service.PSObject.Properties['startupTimeoutSeconds'] -and $service.startupTimeoutSeconds) {
        $timeout = [int]$service.startupTimeoutSeconds
    }

    if ($null -ne $service.PSObject.Properties['port'] -and $service.port) {
        $null = Wait-ServicePort -Name ([string]$service.name) -Port ([int]$service.port) -TimeoutSeconds $timeout
    }

    Write-Host "Started: $($service.name) pid=$($process.Id)"
}
