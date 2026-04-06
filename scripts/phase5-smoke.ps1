$ErrorActionPreference = 'Stop'

$baseUrl = 'http://127.0.0.1:8000'
$headers = @{ 'Content-Type' = 'application/json' }
$suffix = Get-Random -Minimum 100000 -Maximum 999999

function Invoke-Api($method, $path, $body) {
    $payload = if ($null -eq $body) { $null } else { $body | ConvertTo-Json -Depth 8 }
    return Invoke-RestMethod -Method $method -Uri "$baseUrl$path" -Headers $headers -Body $payload
}

function Invoke-ApiExpectStatus($method, $path, $body, $expectedStatus) {
    $payload = if ($null -eq $body) { $null } else { $body | ConvertTo-Json -Depth 8 }

    try {
        Invoke-RestMethod -Method $method -Uri "$baseUrl$path" -Headers $headers -Body $payload | Out-Null
        if ($expectedStatus -ne 200) {
            throw "Expected status $expectedStatus but request succeeded"
        }
    } catch {
        $status = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $status = [int]$_.Exception.Response.StatusCode
        }

        if ($status -ne $expectedStatus) {
            throw "Expected status $expectedStatus but got $status"
        }
    }
}

Write-Host '[Phase5] Creating deterministic test customers'
$customerA = Invoke-Api 'POST' '/api/v1/crm/customers' @{
    tenant_id = 1
    dealer_id = 2
    name = "Phase5 Customer A $suffix"
    email = "phase5.a.$suffix@example.com"
    phone = "7000$suffix"
    city = 'Pune'
    lifecycle_stage = 'ACTIVE'
    source = 'MANUAL'
}
$customerB = Invoke-Api 'POST' '/api/v1/crm/customers' @{
    tenant_id = 1
    dealer_id = 2
    name = "Phase5 Customer B $suffix"
    email = "phase5.b.$suffix@example.com"
    phone = "7111$suffix"
    city = 'Pune'
    lifecycle_stage = 'ACTIVE'
    source = 'MANUAL'
}

if (-not $customerA.ok -or -not $customerB.ok) {
    throw 'Customer creation failed'
}

Write-Host '[Phase5] Validation tightening checks'
Invoke-ApiExpectStatus 'POST' '/api/v1/crm/customers' @{
    tenant_id = 1
    dealer_id = 2
    name = "Invalid Email Customer $suffix"
    email = 'invalid-email'
    lifecycle_stage = 'ACTIVE'
    source = 'MANUAL'
} 422

Invoke-ApiExpectStatus 'POST' '/api/v1/crm/campaigns' @{
    tenant_id = 1
    name = "Invalid Channel Campaign $suffix"
    channel = 'SMS'
    segment_id = 1
    created_by = 2
} 422

Write-Host '[Phase5] Creating lead and enforcing transition rules'
$lead = Invoke-Api 'POST' '/api/v1/crm/leads' @{
    tenant_id = 1
    customer_id = $customerA.data.id
    assigned_to = 2
    title = "Phase5 Lead $suffix"
    source = 'MANUAL'
}

if (-not $lead.ok) {
    throw 'Lead create failed'
}

Invoke-Api 'POST' '/api/v1/crm/leads/transition' @{
    tenant_id = 1
    lead_id = $lead.data.id
    user_id = 2
    new_stage = 'CONTACTED'
    note = 'Initial contact complete'
} | Out-Null

Invoke-Api 'POST' '/api/v1/crm/leads/transition' @{
    tenant_id = 1
    lead_id = $lead.data.id
    user_id = 2
    new_stage = 'QUALIFIED'
    note = 'Qualified for proposal'
} | Out-Null

Invoke-ApiExpectStatus 'POST' '/api/v1/crm/leads/transition' @{
    tenant_id = 1
    lead_id = $lead.data.id
    user_id = 2
    new_stage = 'NEW'
    note = 'Should fail backward transition'
} 422

Write-Host '[Phase5] Segment determinism checks'
$segment = Invoke-Api 'POST' '/api/v1/crm/segments' @{
    tenant_id = 1
    name = "Phase5 Segment $suffix"
    created_by = 2
    rules = @{
        lifecycle_stage = 'ACTIVE'
        city = 'Pune'
    }
}

if (-not $segment.ok) {
    throw 'Segment create failed'
}

$resolvedOne = Invoke-Api 'POST' '/api/v1/crm/segments/resolve' @{
    tenant_id = 1
    segment_id = $segment.data.id
}
$resolvedTwo = Invoke-Api 'POST' '/api/v1/crm/segments/resolve' @{
    tenant_id = 1
    segment_id = $segment.data.id
}

$idsOne = @($resolvedOne.data.customers | ForEach-Object { [int]$_.id })
$idsTwo = @($resolvedTwo.data.customers | ForEach-Object { [int]$_.id })
if (($idsOne -join ',') -ne ($idsTwo -join ',')) {
    throw 'Segment resolution is not deterministic between consecutive calls'
}

Write-Host '[Phase5] Campaign dispatch determinism checks'
$campaign = Invoke-Api 'POST' '/api/v1/crm/campaigns' @{
    tenant_id = 1
    name = "Phase5 Campaign $suffix"
    channel = 'EMAIL'
    segment_id = $segment.data.id
    created_by = 2
}

if (-not $campaign.ok) {
    throw 'Campaign create failed'
}

$dispatch = Invoke-Api 'POST' '/api/v1/crm/campaigns/dispatch' @{
    tenant_id = 1
    campaign_id = $campaign.data.id
}

if (-not $dispatch.ok -or $dispatch.data.status -ne 'COMPLETED') {
    throw 'Campaign dispatch failed'
}

$dispatchAgainExpectedStatus = 422
Invoke-ApiExpectStatus 'POST' '/api/v1/crm/campaigns/dispatch' @{
    tenant_id = 1
    campaign_id = $campaign.data.id
} $dispatchAgainExpectedStatus

Write-Host "[Phase5] PASS | lead_id=$($lead.data.id) segment_id=$($segment.data.id) campaign_id=$($campaign.data.id) recipients=$($dispatch.data.total_recipients)"
