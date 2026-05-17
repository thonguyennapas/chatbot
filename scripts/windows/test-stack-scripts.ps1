$ErrorActionPreference = 'Stop'

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')
$testRoot = Join-Path $repoRoot 'runtime\windows-stack-test'
$wwwRoot = Join-Path $testRoot 'www'
$configPath = Join-Path $testRoot 'stack.test.json'
$port = 47621

$startScript = Join-Path $scriptDir 'start-stack.ps1'
$stopScript = Join-Path $scriptDir 'stop-stack.ps1'
$statusScript = Join-Path $scriptDir 'status-stack.ps1'
$cleanScript = Join-Path $scriptDir 'clean-stack.ps1'

try {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $wwwRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $wwwRoot 'index.html') -Value 'ok' -Encoding ASCII

    $config = [ordered]@{
        schemaVersion = 1
        runtimeRoot = 'runtime/windows-stack-test'
        services = @(
            [ordered]@{
                name = 'test-http'
                enabled = $true
                description = 'Test HTTP server'
                workingDirectory = 'runtime/windows-stack-test/www'
                command = 'python'
                arguments = @('-m', 'http.server', "$port", '--bind', '127.0.0.1')
                port = $port
                startupTimeoutSeconds = 20
            }
        )
        prerequisites = @()
        clean = [ordered]@{
            logGlobs = @('runtime/windows-stack-test/logs/*')
            cacheGlobs = @('runtime/windows-stack-test/tmp/*')
            dataGlobs = @('runtime/windows-stack-test/data/*')
        }
    }

    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8

    & $startScript -Config $configPath -Only test-http

    $statusJson = & $statusScript -Config $configPath -AsJson

    $status = @($statusJson | ConvertFrom-Json)
    Assert-True ($status.Count -eq 1) 'Expected one service status row.'
    Assert-True ([bool]$status[0].isRunning) 'Expected test-http process to be running.'
    Assert-True ([bool]$status[0].isPortOpen) 'Expected test-http port to be open.'

    & $stopScript -Config $configPath -Only test-http

    Start-Sleep -Milliseconds 500
    $statusAfterStopJson = & $statusScript -Config $configPath -AsJson
    $statusAfterStop = @($statusAfterStopJson | ConvertFrom-Json)
    Assert-True (-not [bool]$statusAfterStop[0].isRunning) 'Expected test-http process to be stopped.'

    & $cleanScript -Config $configPath -Logs -Cache

    Write-Host 'PASS: Windows stack scripts smoke test'
}
finally {
    if (Test-Path -LiteralPath $stopScript) {
        & $stopScript -Config $configPath -Only test-http -ErrorAction SilentlyContinue | Out-Null
    }
}
