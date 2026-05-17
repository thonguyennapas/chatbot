Set-StrictMode -Version 2.0

function Get-StackRepoRoot {
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Resolve-StackPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$RepoRoot = (Get-StackRepoRoot)
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Get-DefaultStackConfigPath {
    $repoRoot = Get-StackRepoRoot
    $localConfig = Join-Path $repoRoot 'runtime\windows-stack\stack.local.json'
    if (Test-Path -LiteralPath $localConfig) {
        return $localConfig
    }

    return Join-Path $repoRoot 'scripts\windows\stack.example.json'
}

function Read-StackConfig {
    param([string]$Config)

    $repoRoot = Get-StackRepoRoot
    if ([string]::IsNullOrWhiteSpace($Config)) {
        $configPath = Get-DefaultStackConfigPath
    }
    else {
        $configPath = Resolve-StackPath -Path $Config -RepoRoot $repoRoot
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Stack config not found: $configPath"
    }

    $stack = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if (-not $stack.runtimeRoot) {
        $stack | Add-Member -NotePropertyName runtimeRoot -NotePropertyValue 'runtime/windows-stack' -Force
    }

    $stack | Add-Member -NotePropertyName _configPath -NotePropertyValue $configPath -Force
    $stack | Add-Member -NotePropertyName _repoRoot -NotePropertyValue $repoRoot -Force
    return $stack
}

function Get-StackRuntimeRoot {
    param([Parameter(Mandatory = $true)]$Stack)
    return Resolve-StackPath -Path ([string]$Stack.runtimeRoot) -RepoRoot ([string]$Stack._repoRoot)
}

function Initialize-StackRuntime {
    param([Parameter(Mandatory = $true)]$Stack)

    $runtimeRoot = Get-StackRuntimeRoot -Stack $Stack
    foreach ($child in @('', 'logs', 'pids', 'tmp', 'data')) {
        $path = if ($child) { Join-Path $runtimeRoot $child } else { $runtimeRoot }
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }
}

function Get-SafeServiceName {
    param([Parameter(Mandatory = $true)][string]$Name)
    return ($Name -replace '[^A-Za-z0-9_.-]', '_')
}

function Get-ServicePidPath {
    param(
        [Parameter(Mandatory = $true)]$Stack,
        [Parameter(Mandatory = $true)]$Service
    )

    $safeName = Get-SafeServiceName -Name ([string]$Service.name)
    return Join-Path (Join-Path (Get-StackRuntimeRoot -Stack $Stack) 'pids') "$safeName.pid"
}

function Get-ServiceLogPaths {
    param(
        [Parameter(Mandatory = $true)]$Stack,
        [Parameter(Mandatory = $true)]$Service
    )

    $safeName = Get-SafeServiceName -Name ([string]$Service.name)
    $logRoot = Join-Path (Get-StackRuntimeRoot -Stack $Stack) 'logs'
    return @{
        stdout = Join-Path $logRoot "$safeName.out.log"
        stderr = Join-Path $logRoot "$safeName.err.log"
    }
}

function Get-ManagedPid {
    param(
        [Parameter(Mandatory = $true)]$Stack,
        [Parameter(Mandatory = $true)]$Service
    )

    $pidPath = Get-ServicePidPath -Stack $Stack -Service $Service
    if (-not (Test-Path -LiteralPath $pidPath)) {
        return $null
    }

    $raw = (Get-Content -LiteralPath $pidPath -Raw).Trim()
    if ($raw -match '^\d+$') {
        return [int]$raw
    }

    return $null
}

function Test-PidRunning {
    param([Nullable[int]]$ProcessId)

    if ($null -eq $ProcessId) {
        return $false
    }

    try {
        $null = Get-Process -Id $ProcessId -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Test-TcpPort {
    param(
        [Nullable[int]]$Port,
        [int]$TimeoutMilliseconds = 500
    )

    if ($null -eq $Port -or $Port -le 0) {
        return $false
    }

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false)) {
            return $false
        }

        $client.EndConnect($async)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Get-StackServices {
    param(
        [Parameter(Mandatory = $true)]$Stack,
        [string[]]$Only = @(),
        [switch]$IncludeDisabled
    )

    $requested = @($Only)
    $services = @($Stack.services)
    foreach ($service in $services) {
        if ($requested.Count -gt 0 -and ($requested -notcontains [string]$service.name)) {
            continue
        }

        $enabled = $true
        if ($null -ne $service.PSObject.Properties['enabled']) {
            $enabled = [bool]$service.enabled
        }

        if ($requested.Count -eq 0 -and -not $IncludeDisabled -and -not $enabled) {
            continue
        }

        $service
    }
}

function Resolve-ServiceCommand {
    param(
        [Parameter(Mandatory = $true)]$Stack,
        [Parameter(Mandatory = $true)]$Service
    )

    if (-not $Service.command) {
        throw "Service '$($Service.name)' has no command."
    }

    $command = [string]$Service.command
    if ([System.IO.Path]::IsPathRooted($command) -or $command.Contains('\') -or $command.Contains('/')) {
        $candidate = Resolve-StackPath -Path $command -RepoRoot ([string]$Stack._repoRoot)
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }

        throw "Command for service '$($Service.name)' not found: $candidate"
    }

    $found = Find-StackCommand -Command $command
    if ($null -eq $found) {
        throw "Command for service '$($Service.name)' not found on PATH: $command"
    }

    return $found
}

function Find-StackCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    $found = Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $found) {
        return [string]$found.Source
    }

    $names = @($Command)
    if (-not [System.IO.Path]::GetExtension($Command)) {
        $names = @("$Command.exe", "$Command.cmd", "$Command.bat")
    }

    $candidateRoots = @()
    if ($env:APPDATA) {
        $candidateRoots += Get-ChildItem -Path (Join-Path $env:APPDATA 'Python') -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'Scripts' }
    }
    if ($env:LOCALAPPDATA) {
        $candidateRoots += Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Python') -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'Scripts' }
    }

    foreach ($root in $candidateRoots) {
        foreach ($name in $names) {
            $candidate = Join-Path $root $name
            if (Test-Path -LiteralPath $candidate) {
                return [System.IO.Path]::GetFullPath($candidate)
            }
        }
    }

    return $null
}

function ConvertTo-ArgumentString {
    param([object[]]$Arguments = @())

    $parts = @()
    foreach ($arg in @($Arguments)) {
        if ($null -eq $arg) {
            continue
        }

        $text = [string]$arg
        if ($text -match '[\s"]') {
            $text = '"' + ($text -replace '"', '\"') + '"'
        }

        $parts += $text
    }

    return ($parts -join ' ')
}

function Wait-ServicePort {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Nullable[int]]$Port,
        [int]$TimeoutSeconds = 30
    )

    if ($null -eq $Port -or $Port -le 0) {
        return $true
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-TcpPort -Port $Port -TimeoutMilliseconds 500) {
            return $true
        }

        Start-Sleep -Milliseconds 500
    }

    throw "Service '$Name' did not open port $Port within $TimeoutSeconds seconds."
}

function Get-ServiceStatus {
    param(
        [Parameter(Mandatory = $true)]$Stack,
        [Parameter(Mandatory = $true)]$Service
    )

    $pidPath = Get-ServicePidPath -Stack $Stack -Service $Service
    $pidValue = Get-ManagedPid -Stack $Stack -Service $Service
    $isWindowsService = Test-ServiceUsesWindowsService -Service $Service
    $windowsServiceStatus = $null
    $isRunning = $false

    if ($isWindowsService) {
        $windowsService = Get-Service -Name ([string]$Service.serviceName) -ErrorAction SilentlyContinue
        if ($null -ne $windowsService) {
            $windowsServiceStatus = [string]$windowsService.Status
            $isRunning = $windowsService.Status -eq 'Running'
        }
    }
    else {
        $isRunning = Test-PidRunning -ProcessId $pidValue
    }
    $port = $null
    if ($null -ne $Service.PSObject.Properties['port'] -and $Service.port) {
        $port = [int]$Service.port
    }

    $enabled = $true
    if ($null -ne $Service.PSObject.Properties['enabled']) {
        $enabled = [bool]$Service.enabled
    }

    $command = ''
    if ($null -ne $Service.PSObject.Properties['command']) {
        $command = [string]$Service.command
    }

    $workingDirectory = ''
    if ($null -ne $Service.PSObject.Properties['workingDirectory']) {
        $workingDirectory = [string]$Service.workingDirectory
    }

    $serviceName = ''
    if ($null -ne $Service.PSObject.Properties['serviceName']) {
        $serviceName = [string]$Service.serviceName
    }

    [pscustomobject]@{
        name = [string]$Service.name
        type = if ($isWindowsService) { 'windows-service' } else { 'process' }
        serviceName = $serviceName
        serviceStatus = $windowsServiceStatus
        enabled = $enabled
        pid = $pidValue
        hasPidFile = (Test-Path -LiteralPath $pidPath)
        isRunning = $isRunning
        port = $port
        isPortOpen = (Test-TcpPort -Port $port -TimeoutMilliseconds 300)
        command = $command
        workingDirectory = $workingDirectory
    }
}

function Test-ServiceUsesWindowsService {
    param([Parameter(Mandatory = $true)]$Service)

    if ($null -ne $Service.PSObject.Properties['type'] -and [string]$Service.type -eq 'windows-service') {
        return $true
    }

    return $null -ne $Service.PSObject.Properties['serviceName'] -and -not [string]::IsNullOrWhiteSpace([string]$Service.serviceName)
}

function Assert-PathInsideRepo {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    if ($fullPath -ne $root -and -not $fullPath.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to touch path outside repo root: $fullPath"
    }
}

function Remove-StackPathPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $hasWildcard = $Pattern -match '[\*\?]'
    if ($hasWildcard) {
        $resolvedPattern = if ([System.IO.Path]::IsPathRooted($Pattern)) {
            $Pattern
        }
        else {
            Join-Path $RepoRoot $Pattern
        }
    }
    else {
        $resolvedPattern = Resolve-StackPath -Path $Pattern -RepoRoot $RepoRoot
    }

    $items = @()
    if ($hasWildcard) {
        $items = @(Get-ChildItem -Path $resolvedPattern -Force -ErrorAction SilentlyContinue)
    }
    elseif (Test-Path -LiteralPath $resolvedPattern) {
        $items = @(Get-Item -LiteralPath $resolvedPattern -Force)
    }

    foreach ($item in $items) {
        Assert-PathInsideRepo -Path $item.FullName -RepoRoot $RepoRoot
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
}
