$ErrorActionPreference = 'Stop'

$baseUrl = 'http://127.0.0.1:8000'
$headers = @{ 'Content-Type' = 'application/json' }
$suffix = Get-Random -Minimum 100000 -Maximum 999999

function Invoke-Api($method, $path, $body) {
    $payload = if ($null -eq $body) { $null } else { $body | ConvertTo-Json -Depth 8 }
    return Invoke-RestMethod -Method $method -Uri "$baseUrl$path" -Headers $headers -Body $payload
}

Write-Host '[Phase4] Creating two CRM customers'
$customerOne = Invoke-Api 'POST' '/api/v1/crm/customers' @{
    tenant_id = 1
    dealer_id = 2
    name = "CRM Customer One $suffix"
    email = "crm.one.$suffix@example.com"
    phone = "9000$suffix"
    city = 'Pune'
    lifecycle_stage = 'ACTIVE'
    source = 'MANUAL'
}
if (-not $customerOne.ok) { throw 'Customer one create failed' }
$customerOneId = $customerOne.data.id

$customerTwo = Invoke-Api 'POST' '/api/v1/crm/customers' @{
    tenant_id = 1
    dealer_id = 2
    name = "CRM Customer Two $suffix"
    email = "crm.two.$suffix@example.com"
    phone = "8111$suffix"
    city = 'Pune'
    lifecycle_stage = 'ACTIVE'
    source = 'MANUAL'
}
if (-not $customerTwo.ok) { throw 'Customer two create failed' }
$customerTwoId = $customerTwo.data.id

Write-Host '[Phase4] Creating lead and transitioning stages'
$lead = Invoke-Api 'POST' '/api/v1/crm/leads' @{
    tenant_id = 1
    customer_id = $customerOneId
    assigned_to = 2
    title = "Battery replacement intent $suffix"
    expected_value = 5600
    source = 'WARRANTY'
}
if (-not $lead.ok) { throw 'Lead create failed' }
$leadId = $lead.data.id

$transitionOne = Invoke-Api 'POST' '/api/v1/crm/leads/transition' @{
    tenant_id = 1
    lead_id = $leadId
    user_id = 2
    new_stage = 'CONTACTED'
    note = 'Customer contacted over phone.'
}
if (-not $transitionOne.ok -or $transitionOne.data.stage -ne 'CONTACTED') { throw 'Lead transition CONTACTED failed' }

$transitionTwo = Invoke-Api 'POST' '/api/v1/crm/leads/transition' @{
    tenant_id = 1
    lead_id = $leadId
    user_id = 2
    new_stage = 'QUALIFIED'
    note = 'Confirmed budget and timeline.'
}
if (-not $transitionTwo.ok -or $transitionTwo.data.stage -ne 'QUALIFIED') { throw 'Lead transition QUALIFIED failed' }

Write-Host '[Phase4] Creating segment and resolving recipients'
$segment = Invoke-Api 'POST' '/api/v1/crm/segments' @{
    tenant_id = 1
    name = "Active Pune Segment $suffix"
    created_by = 2
    rules = @{
        lifecycle_stage = 'ACTIVE'
        city = 'Pune'
    }
}
if (-not $segment.ok) { throw 'Segment create failed' }
$segmentId = $segment.data.id

$resolved = Invoke-Api 'POST' '/api/v1/crm/segments/resolve' @{
    tenant_id = 1
    segment_id = $segmentId
}
if (-not $resolved.ok -or $resolved.data.customers.Count -lt 2) { throw 'Segment resolve failed' }

Write-Host '[Phase4] Opting out one customer from email channel'
$optOut = Invoke-Api 'POST' '/api/v1/crm/opt-out' @{
    tenant_id = 1
    customer_id = $customerOneId
    channel = 'EMAIL'
    reason = 'Requested unsubscribe'
}
if (-not $optOut.ok) { throw 'Opt out failed' }

Write-Host '[Phase4] Creating and dispatching campaign'
$campaign = Invoke-Api 'POST' '/api/v1/crm/campaigns' @{
    tenant_id = 1
    name = "Retention Campaign $suffix"
    channel = 'EMAIL'
    segment_id = $segmentId
    created_by = 2
}
if (-not $campaign.ok) { throw 'Campaign create failed' }
$campaignId = $campaign.data.id

$dispatch = Invoke-Api 'POST' '/api/v1/crm/campaigns/dispatch' @{
    tenant_id = 1
    campaign_id = $campaignId
}
if (-not $dispatch.ok) { throw 'Campaign dispatch failed' }
if ($dispatch.data.status -ne 'COMPLETED') { throw 'Campaign status not completed' }
if ([int]$dispatch.data.sent_count -lt 1) { throw 'Campaign sent_count should be at least 1' }

Write-Host "[Phase4] PASS | lead_id=$leadId segment_id=$segmentId campaign_id=$campaignId sent=$($dispatch.data.sent_count)"
