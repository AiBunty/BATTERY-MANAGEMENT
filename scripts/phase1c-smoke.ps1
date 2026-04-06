$ErrorActionPreference = 'Stop'

Write-Host "Phase 1C smoke tests started..." -ForegroundColor Cyan

$base = "http://127.0.0.1:8000"
$tenant = "default"
$suffix = Get-Random -Minimum 100 -Maximum 999
$serial = "XYZ123456$($suffix)AB"

$claimResp = Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    serial = $serial
    dealer_email = "dealer-flow-$suffix@example.com"
    complaint = "Pickup for service"
} | ConvertTo-Json)

$claimId = $claimResp.data.claim_id
if (-not $claimId) {
    Write-Host "FAIL: claim was not created" -ForegroundColor Red
    exit 1
}

$routeResp = Invoke-RestMethod -Method Post -Uri "$base/api/v1/driver/routes" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    driver_email = "driver-flow-$suffix@example.com"
    created_by_email = "admin-flow-$suffix@example.com"
    route_date = (Get-Date).ToString('yyyy-MM-dd')
} | ConvertTo-Json)
$routeId = $routeResp.data.route_id
if (-not $routeId) {
    Write-Host "FAIL: route was not created" -ForegroundColor Red
    exit 1
}

$taskResp = Invoke-RestMethod -Method Post -Uri "$base/api/v1/driver/tasks" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    route_id = $routeId
    claim_id = $claimId
    task_type = "PICKUP_SERVICE"
} | ConvertTo-Json)
$taskId = $taskResp.data.task_id
if (-not $taskId) {
    Write-Host "FAIL: task was not created" -ForegroundColor Red
    exit 1
}

$completeResp = Invoke-RestMethod -Method Post -Uri "$base/api/v1/driver/tasks/complete" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    task_id = $taskId
    batch_photo = "batch-photo-$suffix.webp"
    dealer_signature = "signature-flow-$suffix"
} | ConvertTo-Json)
$handshakeId = $completeResp.data.handshake_id
if (-not $handshakeId) {
    Write-Host "FAIL: handshake was not created" -ForegroundColor Red
    exit 1
}

$inwardResp = Invoke-RestMethod -Method Post -Uri "$base/api/v1/service/inward" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    claim_id = $claimId
    tester_email = "tester-flow-$suffix@example.com"
} | ConvertTo-Json)
$serviceJobId = $inwardResp.data.service_job_id
if (-not $serviceJobId) {
    Write-Host "FAIL: service job was not created" -ForegroundColor Red
    exit 1
}

$diagnoseResp = Invoke-RestMethod -Method Post -Uri "$base/api/v1/service/diagnose" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    service_job_id = $serviceJobId
    diagnosis = "OK"
    diagnosis_notes = "Battery healthy after inspection"
} | ConvertTo-Json)

if ($diagnoseResp.data.claim_status -ne 'READY_FOR_RETURN') {
    Write-Host "FAIL: claim did not move to READY_FOR_RETURN" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: Phase 1C smoke tests" -ForegroundColor Green
Write-Host "Claim ID: $claimId Route ID: $routeId Task ID: $taskId Service Job ID: $serviceJobId"
exit 0
