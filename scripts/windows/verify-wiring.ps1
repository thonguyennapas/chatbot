param(
    [string]$RagflowApi      = 'http://localhost:9380',
    [string]$RagflowApiKey   = '',
    [string]$RagflowDataset  = '',
    [string]$DifyApi         = 'http://localhost:5001',
    [string]$QdrantUrl       = 'http://localhost:6333',
    [string]$ElasticsearchUrl= 'http://localhost:1200',
    [string]$MinioUrl        = 'http://localhost:9000',
    [string]$RedisHost       = '127.0.0.1',
    [int]   $RedisPort       = 6379,
    [string]$PostgresUser    = 'postgres',
    [int]   $PostgresPort    = 5432,
    [string]$PostgresDatabase= 'dify',
    [string]$MysqlUser       = 'root',
    [int]   $MysqlPort       = 3306,
    [string]$MysqlPassword   = '',
    [string]$MysqlDatabase   = 'rag_flow',
    [switch]$AsJson,
    [switch]$SkipDatabases
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'stack-common.ps1')

$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Name, [string]$Target, [bool]$Ok,
        [string]$Details = '', [string]$Hint = '', [int]$DurationMs = 0
    )
    $results.Add([pscustomobject]@{
        name        = $Name
        target      = $Target
        ok          = $Ok
        details     = $Details
        hint        = $Hint
        durationMs  = $DurationMs
    }) | Out-Null
}

function Invoke-HttpCheck {
    param(
        [string]$Name, [string]$Url, [string]$Method = 'GET',
        [hashtable]$Headers = @{}, [string]$Body = '',
        [int[]]$AcceptStatus = @(200, 401, 403),
        [string]$Hint = ''
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = $Method
        $req.Timeout = 5000
        $req.ReadWriteTimeout = 5000
        foreach ($k in $Headers.Keys) { $req.Headers[$k] = [string]$Headers[$k] }

        if ($Body) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
            $req.ContentLength = $bytes.Length
            $req.ContentType = 'application/json'
            $stream = $req.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()
        }

        $resp = $null
        $statusCode = 0
        try { $resp = $req.GetResponse(); $statusCode = [int]$resp.StatusCode }
        catch [System.Net.WebException] {
            if ($null -ne $_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            } else { throw }
        }
        finally { if ($null -ne $resp) { $resp.Close() } }

        $sw.Stop()
        $ok = $AcceptStatus -contains $statusCode
        Add-Result -Name $Name -Target $Url -Ok $ok `
            -Details "HTTP $statusCode" `
            -Hint $(if (-not $ok) { $Hint } else { '' }) `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    }
    catch {
        $sw.Stop()
        Add-Result -Name $Name -Target $Url -Ok $false `
            -Details $_.Exception.Message -Hint $Hint `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    }
}

function Invoke-RedisPing {
    param([string]$HostName, [int]$Port)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.ReceiveTimeout = 2000
        $client.SendTimeout    = 2000
        $async = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(2000, $false)) {
            $sw.Stop()
            Add-Result -Name 'redis: PING' -Target "${HostName}:${Port}" -Ok $false `
                -Details 'TCP timeout' `
                -Hint "Start memurai-redis service. PowerShell may need Admin to start Memurai." `
                -DurationMs ([int]$sw.ElapsedMilliseconds)
            return
        }
        $client.EndConnect($async)

        $stream = $client.GetStream()
        $cmd = [System.Text.Encoding]::ASCII.GetBytes("*1`r`n`$4`r`nPING`r`n")
        $stream.Write($cmd, 0, $cmd.Length); $stream.Flush()
        $buf = New-Object byte[] 64
        $read = $stream.Read($buf, 0, $buf.Length)
        $reply = [System.Text.Encoding]::ASCII.GetString($buf, 0, $read).Trim()
        $sw.Stop()
        $ok = $reply -match '^\+PONG'
        Add-Result -Name 'redis: PING' -Target "${HostName}:${Port}" -Ok $ok `
            -Details "reply=$reply" `
            -Hint $(if (-not $ok) { 'Service answers TCP but not Redis protocol. Check Memurai vs alternative on this port.' } else { '' }) `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    }
    catch {
        $sw.Stop()
        Add-Result -Name 'redis: PING' -Target "${HostName}:${Port}" -Ok $false `
            -Details $_.Exception.Message -DurationMs ([int]$sw.ElapsedMilliseconds)
    }
    finally { $client.Close() }
}

function Invoke-PsqlCheck {
    param([string]$User, [int]$Port, [string]$Database)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $psql = Get-Command 'psql' -ErrorAction SilentlyContinue
    if ($null -eq $psql) {
        $sw.Stop()
        Add-Result -Name 'postgres: database query' -Target "psql -U $User -d $Database -p $Port" -Ok $false `
            -Details "'psql' not on PATH" -Hint 'install-middleware.ps1 -PostgreSQL then reopen terminal.' `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
        return
    }
    try {
        $out = & $psql.Source -U $User -p $Port -d $Database -tAc 'SELECT 1' 2>&1
        $sw.Stop()
        $ok = ($LASTEXITCODE -eq 0) -and ($out.Trim() -eq '1')
        Add-Result -Name 'postgres: database query' -Target "$User@127.0.0.1:$Port/$Database" -Ok $ok `
            -Details "exit=$LASTEXITCODE out=$out" `
            -Hint $(if (-not $ok) { 'setup-databases.ps1 -PostgreSQL; verify pg_hba.conf trust auth.' } else { '' }) `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    } catch {
        $sw.Stop()
        Add-Result -Name 'postgres: database query' -Target "$User@127.0.0.1:$Port/$Database" -Ok $false `
            -Details $_.Exception.Message -DurationMs ([int]$sw.ElapsedMilliseconds)
    }
}

function Invoke-MysqlCheck {
    param([string]$User, [int]$Port, [string]$Database, [string]$Password)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $mysql = Get-Command 'mysql' -ErrorAction SilentlyContinue
    if ($null -eq $mysql) {
        $sw.Stop()
        Add-Result -Name 'mysql: database query' -Target "mysql -u $User -P $Port $Database" -Ok $false `
            -Details "'mysql' client not on PATH" -Hint 'install-middleware.ps1 -MySQL then reopen terminal.' `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
        return
    }
    try {
        $args = @('-u', $User, '-P', "$Port", '--protocol=TCP', $Database, '-e', 'SELECT 1')
        if ($Password) { $args = @("--password=$Password") + $args }
        $out = & $mysql.Source @args 2>&1
        $sw.Stop()
        $ok = ($LASTEXITCODE -eq 0)
        Add-Result -Name 'mysql: database query' -Target "$User@127.0.0.1:$Port/$Database" -Ok $ok `
            -Details "exit=$LASTEXITCODE" `
            -Hint $(if (-not $ok) { 'setup-databases.ps1 -MySQL -MyRootPassword <pass>.' } else { '' }) `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    } catch {
        $sw.Stop()
        Add-Result -Name 'mysql: database query' -Target "$User@127.0.0.1:$Port/$Database" -Ok $false `
            -Details $_.Exception.Message -DurationMs ([int]$sw.ElapsedMilliseconds)
    }
}

# ── Checks ────────────────────────────────────────────────────────────────────

# Memory layer (RAGFlow)
Invoke-HttpCheck -Name 'ragflow: api root' -Url $RagflowApi `
    -Hint 'Start ragflow-api service.'

$ragflowKbUrl = "$RagflowApi/api/v1/dify/retrieval"
$kbBody = if ($RagflowDataset) {
    '{"knowledge_id":"' + $RagflowDataset + '","query":"ping","retrieval_setting":{"top_k":1,"score_threshold":0.0}}'
} else {
    '{"knowledge_id":"verify-wiring","query":"ping","retrieval_setting":{"top_k":1,"score_threshold":0.0}}'
}
$kbHeaders = @{}
if ($RagflowApiKey) { $kbHeaders['Authorization'] = "Bearer $RagflowApiKey" }
Invoke-HttpCheck -Name 'ragflow: external KB endpoint' -Url $ragflowKbUrl -Method 'POST' `
    -Headers $kbHeaders -Body $kbBody -AcceptStatus @(200, 400, 401, 403, 404) `
    -Hint 'Endpoint reachable but verify -RagflowApiKey and -RagflowDataset for full wiring.'

Invoke-HttpCheck -Name 'elasticsearch: cluster info' -Url $ElasticsearchUrl `
    -AcceptStatus @(200, 401) `
    -Hint 'Start elasticsearch service. Check runtime/windows-stack/logs/elasticsearch.err.log.'

Invoke-HttpCheck -Name 'minio: live health' -Url "$MinioUrl/minio/health/live" `
    -AcceptStatus @(200) -Hint 'Start minio service.'

# Brain layer (Dify)
Invoke-HttpCheck -Name 'dify: api health' -Url "$DifyApi/health" `
    -AcceptStatus @(200) -Hint 'Start dify-api service. Check api/.env database settings.'

Invoke-HttpCheck -Name 'qdrant: collections list' -Url "$QdrantUrl/collections" `
    -AcceptStatus @(200) -Hint 'Start qdrant service. Verify binary at runtime/windows-stack/bin/qdrant/qdrant.exe.'

# Shared
Invoke-RedisPing -HostName $RedisHost -Port $RedisPort

# Database queries
if (-not $SkipDatabases) {
    Invoke-PsqlCheck -User $PostgresUser -Port $PostgresPort -Database $PostgresDatabase
    Invoke-MysqlCheck -User $MysqlUser -Port $MysqlPort -Database $MysqlDatabase -Password $MysqlPassword
}

# ── Output ────────────────────────────────────────────────────────────────────
if ($AsJson) {
    $results | ConvertTo-Json -Depth 4
}
else {
    Write-Host ""
    Write-Host ("{0,-32} {1,-6} {2,8}  {3}" -f 'Check', 'Result', 'Time', 'Target')
    Write-Host ("{0,-32} {1,-6} {2,8}  {3}" -f ('-' * 32), '------', '--------', ('-' * 40))
    foreach ($r in $results) {
        $mark = if ($r.ok) { 'OK' } else { 'FAIL' }
        Write-Host ("{0,-32} {1,-6} {2,6}ms  {3}" -f $r.name, $mark, $r.durationMs, $r.target)
        if (-not $r.ok -and $r.details) { Write-Host "    details: $($r.details)" -ForegroundColor DarkGray }
        if (-not $r.ok -and $r.hint)    { Write-Host "    hint:    $($r.hint)"    -ForegroundColor Yellow }
    }
    Write-Host ""
    $failed = @($results | Where-Object { -not $_.ok }).Count
    $passed = @($results | Where-Object { $_.ok }).Count
    Write-Host "Passed: $passed   Failed: $failed"
}

if (@($results | Where-Object { -not $_.ok }).Count -gt 0) { exit 1 }
exit 0
