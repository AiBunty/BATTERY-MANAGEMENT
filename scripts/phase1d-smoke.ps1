$ErrorActionPreference = 'Stop'

Write-Host "Phase 1D smoke tests started..." -ForegroundColor Cyan

$base = "http://127.0.0.1:8000"
$suffix = Get-Random -Minimum 100 -Maximum 999
$email = "dealer-phase1d-$suffix@example.com"

$send = Invoke-RestMethod -Method Post -Uri "$base/api/v1/auth/send-otp" -ContentType "application/json" -Body (@{ tenant_slug = "default"; email = $email } | ConvertTo-Json)
$otp = $send.data.debug_otp
if (-not $otp) {
    Write-Host "FAIL: OTP not returned for local smoke test" -ForegroundColor Red
    exit 1
}

$verify = Invoke-RestMethod -Method Post -Uri "$base/api/v1/auth/verify-otp" -ContentType "application/json" -Body (@{ tenant_slug = "default"; email = $email; otp = $otp } | ConvertTo-Json)
$refreshToken = $verify.data.refresh_token
if (-not $refreshToken -or -not $verify.data.access_token) {
    Write-Host "FAIL: verify did not return tokens" -ForegroundColor Red
    exit 1
}

$refresh = Invoke-RestMethod -Method Post -Uri "$base/api/v1/auth/refresh" -ContentType "application/json" -Body (@{ tenant_slug = "default"; refresh_token = $refreshToken } | ConvertTo-Json)
$newRefresh = $refresh.data.refresh_token
if (-not $newRefresh -or $newRefresh -eq $refreshToken) {
    Write-Host "FAIL: refresh token was not rotated" -ForegroundColor Red
    exit 1
}

$logout = Invoke-RestMethod -Method Post -Uri "$base/api/v1/auth/logout" -ContentType "application/json" -Body (@{ tenant_slug = "default"; refresh_token = $newRefresh } | ConvertTo-Json)
if (-not $logout.success) {
    Write-Host "FAIL: logout did not succeed" -ForegroundColor Red
    exit 1
}

$failedStatus = 0
try {
    Invoke-RestMethod -Method Post -Uri "$base/api/v1/auth/refresh" -ContentType "application/json" -Body (@{ tenant_slug = "default"; refresh_token = $newRefresh } | ConvertTo-Json) | Out-Null
    $failedStatus = 200
} catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $failedStatus = [int] $_.Exception.Response.StatusCode
    }
}

if ($failedStatus -ne 401) {
    Write-Host "FAIL: revoked refresh token should return 401" -ForegroundColor Red
    exit 1
}

$claim = Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims" -ContentType "application/json" -Body (@{ tenant_slug = "default"; serial = "DLV123456$($suffix)AB"; dealer_email = "dealer-incentive-$suffix@example.com"; complaint = "Delivery incentive test" } | ConvertTo-Json)
$route = Invoke-RestMethod -Method Post -Uri "$base/api/v1/driver/routes" -ContentType "application/json" -Body (@{ tenant_slug = "default"; driver_email = "driver-incentive-$suffix@example.com"; created_by_email = "admin-incentive-$suffix@example.com"; route_date = (Get-Date).ToString('yyyy-MM-dd') } | ConvertTo-Json)
$task = Invoke-RestMethod -Method Post -Uri "$base/api/v1/driver/tasks" -ContentType "application/json" -Body (@{ tenant_slug = "default"; route_id = $route.data.route_id; claim_id = $claim.data.claim_id; task_type = "DELIVERY_NEW" } | ConvertTo-Json)
$complete = Invoke-RestMethod -Method Post -Uri "$base/api/v1/driver/tasks/complete" -ContentType "application/json" -Body (@{ tenant_slug = "default"; task_id = $task.data.task_id; batch_photo = "delivery-batch-$suffix.webp"; dealer_signature = "delivery-signature-$suffix" } | ConvertTo-Json)

if (-not $complete.data.handshake_id) {
    Write-Host "FAIL: delivery handshake not created" -ForegroundColor Red
    exit 1
}

$query = docker exec -e MYSQL_PWD=root bm-mysql mysql -N -uroot -D battery_db -e "SELECT COUNT(*) FROM delivery_incentives WHERE task_id = $($task.data.task_id);"
if ($query.Trim() -ne '1') {
    Write-Host "FAIL: delivery incentive row not created" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: Phase 1D smoke tests" -ForegroundColor Green
exit 0
