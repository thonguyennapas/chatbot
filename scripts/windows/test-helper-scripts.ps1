$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Resolve-Path (Join-Path $scriptDir '..\..')
$testRoot  = Join-Path $repoRoot 'runtime\helper-test'

if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

try {
    # -- install-middleware.ps1 -DryRun -All ----------------------------------─
    Write-Host "TEST: install-middleware.ps1 -DryRun -All"
    $installScript = Join-Path $scriptDir 'install-middleware.ps1'
    $installOut = & $installScript -All -DryRun *>&1 | Out-String
    Assert-True ($installOut -match 'PostgreSQL.PostgreSQL.17') 'install-middleware should mention PostgreSQL 17 package id'
    Assert-True ($installOut -match 'Oracle.MySQL')             'install-middleware should mention Oracle.MySQL package id'
    Assert-True ($installOut -match 'MinIO.Server')             'install-middleware should mention MinIO.Server package id'
    Assert-True ($installOut -match 'elasticsearch-8.11.3-windows-x86_64.zip') 'install-middleware should reference Elasticsearch 8.11.3 zip'
    Assert-True ($installOut -match 'qdrant-x86_64-pc-windows-msvc.zip')       'install-middleware should reference Qdrant zip'
    Assert-True ($installOut -match 'VECTOR_STORE=qdrant')                     'install-middleware should remind to set VECTOR_STORE=qdrant'
    Assert-True ($installOut -match 'DRY RUN')                                  'install-middleware should label dry-run output'
    Write-Host "PASS: install-middleware.ps1 -DryRun -All"

    # -- install-middleware.ps1 with no flags shows usage ----------------------
    Write-Host "TEST: install-middleware.ps1 with no flags"
    $usageOut = & $installScript *>&1 | Out-String
    Assert-True ($usageOut -match 'No component selected') 'install-middleware should print usage when nothing is requested'
    Write-Host "PASS: install-middleware.ps1 no-flag usage"

    # -- setup-databases.ps1 -DryRun -All --------------------------------------
    Write-Host "TEST: setup-databases.ps1 -DryRun -All"
    $setupScript = Join-Path $scriptDir 'setup-databases.ps1'
    $setupOut = & $setupScript -All -DryRun *>&1 | Out-String
    Assert-True ($setupOut -match 'DRY RUN: initdb')                          'setup-databases should dry-run initdb'
    Assert-True ($setupOut -match 'DRY RUN: mysqld --initialize-insecure')    'setup-databases should dry-run mysqld --initialize-insecure'
    Assert-True ($setupOut -match 'DRY RUN: start postgres')                  'setup-databases should mention starting postgres'
    Assert-True ($setupOut -match 'DRY RUN: start mysqld')                    'setup-databases should mention starting mysqld'
    Write-Host "PASS: setup-databases.ps1 -DryRun -All"

    # -- setup-databases.ps1 with no flags shows usage ------------------------─
    Write-Host "TEST: setup-databases.ps1 with no flags"
    $setupUsage = & $setupScript *>&1 | Out-String
    Assert-True ($setupUsage -match 'No database selected') 'setup-databases should print usage when nothing is requested'
    Write-Host "PASS: setup-databases.ps1 no-flag usage"

    # -- configure-dify-env.ps1 -- full lifecycle ------------------------------─
    Write-Host "TEST: configure-dify-env.ps1 -- full lifecycle"

    # Build a fake Dify api directory with a realistic .env.example
    $fakeApiDir = Join-Path $testRoot 'dify\api'
    New-Item -ItemType Directory -Force -Path $fakeApiDir | Out-Null

    # Sample .env.example with Weaviate set, no VECTOR_STORE yet
    $sampleEnv = @(
        '# Sample Dify env'
        'DB_HOST=db'
        'DB_PORT=5432'
        'DB_USERNAME=postgres'
        'DB_PASSWORD=oldpw'
        'DB_DATABASE=dify'
        ''
        'REDIS_HOST=redis'
        'REDIS_PORT=6379'
        'REDIS_PASSWORD=oldredis'
        'REDIS_USE_SSL=false'
        ''
        'WEAVIATE_ENDPOINT=http://weaviate:8080'
        'WEAVIATE_API_KEY=oldkey'
        ''
        'SECRET_KEY=please-keep-this'
        'CONSOLE_API_URL=http://localhost:5001'
    )
    $examplePath = Join-Path $fakeApiDir '.env.example'
    Set-Content -LiteralPath $examplePath -Value $sampleEnv -Encoding UTF8

    $configScript = Join-Path $scriptDir 'configure-dify-env.ps1'
    $relEnvFile     = 'runtime/helper-test/dify/api/.env'
    $relExampleFile = 'runtime/helper-test/dify/api/.env.example'

    # First run: .env does not exist, must seed from .env.example then update
    & $configScript -EnvFile $relEnvFile -ExampleFile $relExampleFile -DbPassword 'newpw' -RedisPassword 'newredis' -NoBackup | Out-Null

    $envPath = Join-Path $fakeApiDir '.env'
    Assert-True (Test-Path -LiteralPath $envPath) '.env should be created when seeded from example'

    $envContent = Get-Content -LiteralPath $envPath

    # Updated keys
    Assert-True ($envContent -contains 'VECTOR_STORE=qdrant')           'VECTOR_STORE should be appended as qdrant'
    Assert-True ($envContent -contains 'QDRANT_URL=http://127.0.0.1:6333') 'QDRANT_URL should be appended'
    Assert-True ($envContent -contains 'DB_HOST=127.0.0.1')             'DB_HOST should be replaced with 127.0.0.1'
    Assert-True ($envContent -contains 'DB_PASSWORD=newpw')             'DB_PASSWORD should be updated to newpw'
    Assert-True ($envContent -contains 'REDIS_PASSWORD=newredis')       'REDIS_PASSWORD should be updated to newredis'

    # Weaviate keys must be commented out, not deleted
    $weaviateLines = $envContent | Where-Object { $_ -match 'WEAVIATE_ENDPOINT' }
    Assert-True (@($weaviateLines).Count -eq 1) 'WEAVIATE_ENDPOINT line should still exist exactly once'
    Assert-True (@($weaviateLines)[0] -match '^# replaced-by-qdrant:') 'WEAVIATE_ENDPOINT should be commented with replaced-by-qdrant prefix'

    # Untouched keys remain
    Assert-True ($envContent -contains 'SECRET_KEY=please-keep-this')       'SECRET_KEY should be preserved'
    Assert-True ($envContent -contains 'CONSOLE_API_URL=http://localhost:5001') 'CONSOLE_API_URL should be preserved'

    # CELERY_BROKER_URL with password embedded
    $celery = $envContent | Where-Object { $_ -match '^CELERY_BROKER_URL=' }
    Assert-True (@($celery).Count -eq 1)                                  'CELERY_BROKER_URL should be present'
    Assert-True (@($celery)[0] -match 'redis://:newredis@127.0.0.1:6379/1') 'CELERY_BROKER_URL should embed the redis password'

    Write-Host "PASS: configure-dify-env.ps1 seeded from example and applied updates"

    # Second run: idempotent update with a different DB_PASSWORD, with backup
    & $configScript -EnvFile $relEnvFile -ExampleFile $relExampleFile -DbPassword 'rotated' -RedisPassword 'newredis' | Out-Null

    $envContent2 = Get-Content -LiteralPath $envPath
    Assert-True ($envContent2 -contains 'DB_PASSWORD=rotated') 'DB_PASSWORD should be updated to rotated on second run'
    $backupCount = @(Get-ChildItem -Path "$envPath.bak.*" -ErrorAction SilentlyContinue).Count
    Assert-True ($backupCount -ge 1) 'A timestamped .bak file should exist after second run (NoBackup omitted)'

    # No duplicate VECTOR_STORE lines after second run
    $vectorLines = @($envContent2 | Where-Object { $_ -match '^VECTOR_STORE=' })
    Assert-True ($vectorLines.Count -eq 1) "VECTOR_STORE must appear exactly once after idempotent run (found $($vectorLines.Count))"

    Write-Host "PASS: configure-dify-env.ps1 second run idempotent + backup created"

    # Third run: -DryRun should not modify the file
    $beforeHash = (Get-FileHash -LiteralPath $envPath).Hash
    & $configScript -EnvFile $relEnvFile -ExampleFile $relExampleFile -DbPassword 'should-not-stick' -DryRun | Out-Null
    $afterHash  = (Get-FileHash -LiteralPath $envPath).Hash
    Assert-True ($beforeHash -eq $afterHash) '-DryRun must not modify the .env file'

    Write-Host "PASS: configure-dify-env.ps1 -DryRun makes no file changes"

    # -- verify-wiring.ps1 -- JSON output is parseable --------------------------
    Write-Host "TEST: verify-wiring.ps1 -AsJson -SkipDatabases (offline)"
    $verifyScript = Join-Path $scriptDir 'verify-wiring.ps1'
    $verifyOut = & $verifyScript -AsJson -SkipDatabases 2>&1
    $verifyJson = ($verifyOut | Where-Object { $_ -match '^\s*[\[{]' -or $_ -match '^\s*\]' -or $_ -match '^\s*"' -or $_ -match '^\s*}' -or $_ -match '^\s*,' }) -join "`n"
    $parsed = $verifyJson | ConvertFrom-Json
    $rows = @($parsed)
    Assert-True ($rows.Count -ge 6) "verify-wiring should emit at least 6 check rows (got $($rows.Count))"
    foreach ($r in $rows) {
        Assert-True ($null -ne $r.name)   'each check row must have a name'
        Assert-True ($null -ne $r.target) 'each check row must have a target'
        Assert-True ($r.PSObject.Properties.Name -contains 'ok') 'each check row must have ok'
    }
    Write-Host "PASS: verify-wiring.ps1 JSON output shape"

    Write-Host ""
    Write-Host "ALL HELPER SCRIPT TESTS PASSED"
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
