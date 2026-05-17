param()

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$service = Get-Service -Name 'Memurai' -ErrorAction SilentlyContinue
if ($null -eq $service) {
    Write-Host 'SKIP: Memurai service is not installed on this machine.'
    exit 0
}

$runtimeRoot = Join-Path $repoRoot 'runtime\windows-stack-test-service-permissions'
$configPath = Join-Path $runtimeRoot 'stack.local.json'
New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null

$config = [ordered]@{
    schemaVersion = 1
    runtimeRoot = 'runtime/windows-stack-test-service-permissions'
    prerequisites = @()
    services = @(
        [ordered]@{
            name = 'test-memurai'
            type = 'windows-service'
            enabled = $true
            serviceName = 'Memurai'
            port = 6379
            startupTimeoutSeconds = 2
        }
    )
    clean = [ordered]@{
        logGlobs = @('runtime/windows-stack-test-service-permissions/logs/*')
        cacheGlobs = @('runtime/windows-stack-test-service-permissions/tmp/*')
        dataGlobs = @()
    }
}

$config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding ASCII

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$output = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'start-stack.ps1') -Config $configPath -Only test-memurai 2>&1
$exitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
$text = $output | Out-String

if ($exitCode -eq 0) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'stop-stack.ps1') -Config $configPath -Only test-memurai | Out-Null
    Write-Host 'SKIP: current session can start Memurai, so permission guidance was not exercised.'
    exit 0
}

if ($text -notmatch 'Administrator|service control permissions') {
    throw "Expected Windows service permission guidance, got:`n$text"
}

Write-Host 'PASS: Windows service permission guidance'
