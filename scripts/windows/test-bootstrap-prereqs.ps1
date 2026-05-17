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
$bootstrapScript = Join-Path $scriptDir 'bootstrap.ps1'

$jsonText = (& $bootstrapScript -PrerequisitesJson) -join "`n"
$rows = @($jsonText | ConvertFrom-Json | ForEach-Object { $_ })

Assert-True ($rows.Count -gt 0) 'Expected prerequisite rows.'
$nodeRows = @($rows | Where-Object { $_.name -eq 'Node.js' })
$pythonRows = @($rows | Where-Object { $_.name -eq 'Python' })
Assert-True ($nodeRows.Count -eq 1) 'Expected Node.js prerequisite row.'
Assert-True ($pythonRows.Count -eq 1) 'Expected Python prerequisite row.'
Assert-True ([bool]$nodeRows[0].isAvailable) 'Expected Node.js to be available.'
Assert-True ([bool]$pythonRows[0].isAvailable) 'Expected Python to be available.'

Write-Host 'PASS: bootstrap prerequisite JSON'
