$ErrorActionPreference = 'Stop'

Write-Host "Phase 1A smoke tests started..." -ForegroundColor Cyan

$base = "http://127.0.0.1:8000"
$email = "dealer1@example.com"

$sendBody = @{ tenant_slug = "default"; email = $email } | ConvertTo-Json
$send = Invoke-RestMethod -Method Post -Uri "$base/api/v1/auth/send-otp" -ContentType "application/json" -Body $sendBody

if (-not $send.success) {
    Write-Host "FAIL: send-otp endpoint did not succeed" -ForegroundColor Red
    exit 1
}

$otp = $send.data.debug_otp
if (-not $otp) {
    Write-Host "FAIL: debug OTP not returned in local mode" -ForegroundColor Red
    exit 1
}

$verifyBody = @{ tenant_slug = "default"; email = $email; otp = $otp } | ConvertTo-Json
$verify = Invoke-RestMethod -Method Post -Uri "$base/api/v1/auth/verify-otp" -ContentType "application/json" -Body $verifyBody

if (-not $verify.success) {
    Write-Host "FAIL: verify-otp endpoint did not succeed" -ForegroundColor Red
    exit 1
}

if (-not $verify.data.access_token -or -not $verify.data.refresh_token) {
    Write-Host "FAIL: tokens not returned" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: Phase 1A smoke tests" -ForegroundColor Green
exit 0
