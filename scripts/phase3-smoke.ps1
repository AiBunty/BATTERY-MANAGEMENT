$ErrorActionPreference = 'Stop'

Write-Host "Phase 3 smoke tests started..." -ForegroundColor Cyan

$base = "http://127.0.0.1:8000"
$tenant = "default"
$suffix = Get-Random -Minimum 100 -Maximum 999

# Ensure plan quota guard can be tested relative to current month usage
$tenantId = docker exec -e MYSQL_PWD=root bm-mysql mysql -N -uroot -D battery_db -e "SELECT id FROM tenants WHERE slug='default' LIMIT 1;"
$tenantId = $tenantId.Trim()
$currentCount = docker exec -e MYSQL_PWD=root bm-mysql mysql -N -uroot -D battery_db -e "SELECT COUNT(*) FROM claims WHERE tenant_id=$tenantId AND DATE_FORMAT(created_at,'%Y-%m')=DATE_FORMAT(NOW(),'%Y-%m');"
$currentCount = [int]$currentCount.Trim()
$quotaLimit = $currentCount + 1
docker exec -e MYSQL_PWD=root bm-mysql mysql -N -uroot -D battery_db -e "UPDATE plans p JOIN tenants t ON t.plan_id=p.id SET p.max_monthly_claims=$quotaLimit WHERE t.id=$tenantId;" | Out-Null

# Create one claim (should pass)
$claim1 = Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims" -ContentType "application/json" -Headers @{ 'Idempotency-Key' = "idem-$suffix-a" } -Body (@{
    tenant_slug = $tenant
    serial = "P3A123456$($suffix)AB"
    dealer_email = "dealer-phase3-$suffix@example.com"
    complaint = "Phase 3 first claim"
} | ConvertTo-Json)
if (-not $claim1.success) {
    Write-Host "FAIL: first claim should succeed" -ForegroundColor Red
    exit 1
}

# Idempotency replay should return same claim_number
$claim1Replay = Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims" -ContentType "application/json" -Headers @{ 'Idempotency-Key' = "idem-$suffix-a" } -Body (@{
    tenant_slug = $tenant
    serial = "P3A123456$($suffix)AB"
    dealer_email = "dealer-phase3-$suffix@example.com"
    complaint = "Phase 3 first claim"
} | ConvertTo-Json)
if ($claim1Replay.data.claim_number -ne $claim1.data.claim_number) {
    Write-Host "FAIL: idempotency replay did not return same response" -ForegroundColor Red
    exit 1
}

# Second claim should fail due to quota limit=current+1
$quotaStatus = 0
try {
    Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims" -ContentType "application/json" -Headers @{ 'Idempotency-Key' = "idem-$suffix-b" } -Body (@{
        tenant_slug = $tenant
        serial = "P3B123456$($suffix)AB"
        dealer_email = "dealer-phase3-$suffix@example.com"
        complaint = "Phase 3 quota hit"
    } | ConvertTo-Json) | Out-Null
    $quotaStatus = 200
} catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $quotaStatus = [int] $_.Exception.Response.StatusCode
    }
}
if ($quotaStatus -ne 429) {
    Write-Host "FAIL: expected quota rejection (429)" -ForegroundColor Red
    exit 1
}

# Reset quota so remaining tests can continue
$reset = docker exec -e MYSQL_PWD=root bm-mysql mysql -N -uroot -D battery_db -e "UPDATE plans p JOIN tenants t ON t.plan_id=p.id SET p.max_monthly_claims=1000 WHERE t.id=$tenantId;"

# Tracking lookup and resolve
$ticket = $claim1.data.claim_number
$lookup = Invoke-RestMethod -Method Post -Uri "$base/api/v1/track/lookup" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    ticket_number = $ticket
} | ConvertTo-Json)
if (-not $lookup.success -or -not $lookup.data.token) {
    Write-Host "FAIL: tracking lookup did not return token" -ForegroundColor Red
    exit 1
}

$track = Invoke-RestMethod -Method Get -Uri "$base/api/v1/track/$($lookup.data.token)"
if (-not $track.success -or -not $track.data.claim_number) {
    Write-Host "FAIL: tracking resolve did not return claim data" -ForegroundColor Red
    exit 1
}

# Invalid token should be 404
$invalidStatus = 0
try {
    Invoke-RestMethod -Method Get -Uri "$base/api/v1/track/invalidtoken" | Out-Null
    $invalidStatus = 200
} catch {
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $invalidStatus = [int] $_.Exception.Response.StatusCode
    }
}
if ($invalidStatus -ne 404) {
    Write-Host "FAIL: invalid tracking token should return 404" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: Phase 3 smoke tests" -ForegroundColor Green
exit 0
