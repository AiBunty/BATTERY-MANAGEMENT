$ErrorActionPreference = 'Stop'

Write-Host 'Pre-release checks started...' -ForegroundColor Cyan

$steps = @(
    'powershell -ExecutionPolicy Bypass -File .\scripts\run-migrations.ps1',
    'powershell -ExecutionPolicy Bypass -File .\scripts\phase5-gate.ps1'
)

foreach ($step in $steps) {
    Write-Host "Running: $step" -ForegroundColor Gray
    Invoke-Expression $step
    if ($LASTEXITCODE -ne 0) {
        Write-Host "PRE-RELEASE FAIL at: $step" -ForegroundColor Red
        exit 1
    }
}

Write-Host 'PRE-RELEASE PASS' -ForegroundColor Green
exit 0
