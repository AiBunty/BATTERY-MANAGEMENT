$ErrorActionPreference = 'Stop'

Write-Host 'Phase 5 gate started...' -ForegroundColor Cyan

$checks = @(
    'php -l app/Modules/CRM/Services/CrmService.php',
    'php -l app/Modules/CRM/Controllers/CrmController.php',
    'powershell -ExecutionPolicy Bypass -File .\scripts\phase5-contract-smoke.ps1',
    'powershell -ExecutionPolicy Bypass -File .\scripts\phase5-smoke.ps1',
    'powershell -ExecutionPolicy Bypass -File .\scripts\phase4-smoke.ps1',
    'powershell -ExecutionPolicy Bypass -File .\scripts\phase1a-smoke.ps1',
    'powershell -ExecutionPolicy Bypass -File .\scripts\phase1d-smoke.ps1',
    'powershell -ExecutionPolicy Bypass -File .\scripts\phase2-smoke.ps1',
    'powershell -ExecutionPolicy Bypass -File .\scripts\phase3-smoke.ps1'
)

foreach ($cmd in $checks) {
    Write-Host "Running: $cmd" -ForegroundColor Gray
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Phase 5 gate FAIL at: $cmd" -ForegroundColor Red
        exit 1
    }
}

Write-Host 'Phase 5 gate PASS' -ForegroundColor Green
exit 0
