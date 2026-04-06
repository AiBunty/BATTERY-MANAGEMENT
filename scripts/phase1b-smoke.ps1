$ErrorActionPreference = 'Stop'

Write-Host "Phase 1B smoke tests started..." -ForegroundColor Cyan

$base = "http://127.0.0.1:8000"
$serial = "ABC1234567890AB"

$checkBody = @{ tenant_slug = "default"; serial = $serial } | ConvertTo-Json
$check = Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims/check-serial" -ContentType "application/json" -Body $checkBody

if (-not $check.success) {
    Write-Host "FAIL: check-serial did not succeed" -ForegroundColor Red
    exit 1
}

$createBody = @{
    tenant_slug = "default"
    serial = $serial
    dealer_email = "dealer1@example.com"
    complaint = "Battery not charging"
} | ConvertTo-Json

$create = Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims" -ContentType "application/json" -Body $createBody

if (-not $create.success) {
    Write-Host "FAIL: claim create did not succeed" -ForegroundColor Red
    exit 1
}

if (-not $create.data.claim_number) {
    Write-Host "FAIL: claim number not returned" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: Phase 1B smoke tests" -ForegroundColor Green
Write-Host "Claim Number: $($create.data.claim_number)"
exit 0
