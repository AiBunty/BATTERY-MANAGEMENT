$ErrorActionPreference = 'Stop'

Write-Host "Phase 2 smoke tests started..." -ForegroundColor Cyan

$base = "http://127.0.0.1:8000"
$tenant = "default"
$suffix = Get-Random -Minimum 100 -Maximum 999
$serial = "LMN123456$($suffix)AB"

# Create duplicate claims on same battery so lemon report has one flagged row
Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    serial = $serial
    dealer_email = "dealer-report-$suffix@example.com"
    complaint = "Repeat issue 1"
} | ConvertTo-Json) | Out-Null

Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    serial = $serial
    dealer_email = "dealer-report-$suffix@example.com"
    complaint = "Repeat issue 2"
} | ConvertTo-Json) | Out-Null

# Tally import
$rows = @(
    @{ serial = "TLY123456$($suffix)AB" },
    @{ serial = "TLY223456$($suffix)AB" },
    @{ serial = $serial }
)
$tallyImport = Invoke-RestMethod -Method Post -Uri "$base/api/v1/tally/import" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    imported_by_email = "admin-tally-$suffix@example.com"
    filename = "phase2-$suffix.json"
    rows = $rows
} | ConvertTo-Json -Depth 5)

if (-not $tallyImport.success) {
    Write-Host "FAIL: tally import did not succeed" -ForegroundColor Red
    exit 1
}

# Delivery incentive path for finance report
$claim = Invoke-RestMethod -Method Post -Uri "$base/api/v1/claims" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    serial = "FIN123456$($suffix)AB"
    dealer_email = "dealer-finance-$suffix@example.com"
    complaint = "Finance report driver flow"
} | ConvertTo-Json)
$route = Invoke-RestMethod -Method Post -Uri "$base/api/v1/driver/routes" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    driver_email = "driver-finance-$suffix@example.com"
    created_by_email = "admin-finance-$suffix@example.com"
    route_date = (Get-Date).ToString('yyyy-MM-dd')
} | ConvertTo-Json)
$task = Invoke-RestMethod -Method Post -Uri "$base/api/v1/driver/tasks" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    route_id = $route.data.route_id
    claim_id = $claim.data.claim_id
    task_type = "DELIVERY_NEW"
} | ConvertTo-Json)
Invoke-RestMethod -Method Post -Uri "$base/api/v1/driver/tasks/complete" -ContentType "application/json" -Body (@{
    tenant_slug = $tenant
    task_id = $task.data.task_id
    batch_photo = "phase2-batch-$suffix.webp"
    dealer_signature = "phase2-signature-$suffix"
} | ConvertTo-Json) | Out-Null

$lemon = Invoke-RestMethod -Method Post -Uri "$base/api/v1/reports/lemon" -ContentType "application/json" -Body (@{ tenant_slug = $tenant } | ConvertTo-Json)
if (-not $lemon.success -or $lemon.data.Count -lt 1) {
    Write-Host "FAIL: lemon report returned no flagged batteries" -ForegroundColor Red
    exit 1
}

$finance = Invoke-RestMethod -Method Post -Uri "$base/api/v1/reports/finance" -ContentType "application/json" -Body (@{ tenant_slug = $tenant; month = (Get-Date).ToString('yyyy-MM') } | ConvertTo-Json)
if (-not $finance.success -or $finance.data.Count -lt 1) {
    Write-Host "FAIL: finance report returned no incentive rows" -ForegroundColor Red
    exit 1
}

$export = Invoke-RestMethod -Method Post -Uri "$base/api/v1/tally/export" -ContentType "application/json" -Body (@{ tenant_slug = $tenant; exported_by_email = "admin-tally-$suffix@example.com" } | ConvertTo-Json)
if (-not $export.success -or -not ($export.data.csv -match 'serial_number;status;is_in_tally')) {
    Write-Host "FAIL: tally export did not return csv content" -ForegroundColor Red
    exit 1
}

$audit = Invoke-RestMethod -Method Post -Uri "$base/api/v1/reports/audit-summary" -ContentType "application/json" -Body (@{ tenant_slug = $tenant } | ConvertTo-Json)
if (-not $audit.success -or $audit.data.Count -lt 1) {
    Write-Host "FAIL: audit summary returned no rows" -ForegroundColor Red
    exit 1
}

Write-Host "PASS: Phase 2 smoke tests" -ForegroundColor Green
exit 0
