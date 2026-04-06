$ErrorActionPreference = 'Stop'

$baseUrl = 'http://127.0.0.1:8000'
$headers = @{ 'Content-Type' = 'application/json' }
$suffix = Get-Random -Minimum 100000 -Maximum 999999

function Invoke-Json($method, $path, $body) {
    $payload = if ($null -eq $body) { $null } else { $body | ConvertTo-Json -Depth 8 }
    return Invoke-RestMethod -Method $method -Uri "$baseUrl$path" -Headers $headers -Body $payload
}

function Assert-SuccessEnvelope($resp, $label) {
    if (-not ($resp.PSObject.Properties.Name -contains 'success')) { throw "$label missing success" }
    if (-not ($resp.PSObject.Properties.Name -contains 'ok')) { throw "$label missing ok" }
    if (-not ($resp.PSObject.Properties.Name -contains 'data')) { throw "$label missing data" }
    if (-not ($resp.PSObject.Properties.Name -contains 'error')) { throw "$label missing error" }
    if (-not $resp.success -or -not $resp.ok) { throw "$label expected success envelope" }
    if ($null -ne $resp.error) { throw "$label expected null error" }
}

function Assert-ValidationEnvelope($method, $path, $body, $label) {
    $payload = if ($null -eq $body) { $null } else { $body | ConvertTo-Json -Depth 8 }

    $status = 0
    $content = $null

    try {
        Invoke-RestMethod -Method $method -Uri "$baseUrl$path" -Headers $headers -Body $payload | Out-Null
        throw "$label expected 422 response"
    } catch {
        $resp = $_.Exception.Response

        if ($resp -and $resp.PSObject.Properties.Name -contains 'StatusCode') {
            if ($resp.StatusCode -and $resp.StatusCode.PSObject.Properties.Name -contains 'value__') {
                $status = [int]$resp.StatusCode.value__
            } else {
                $status = [int]$resp.StatusCode
            }
        }

        if ($resp -and $resp.PSObject.Properties.Name -contains 'Content' -and $resp.Content -ne $null) {
            $content = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        } elseif ($resp -and $resp.PSObject.Methods.Name -contains 'GetResponseStream') {
            $stream = $resp.GetResponseStream()
            if ($stream -ne $null) {
                $reader = New-Object System.IO.StreamReader($stream)
                $content = $reader.ReadToEnd()
            }
        }

        if (-not $content -and $_.ErrorDetails -and $_.ErrorDetails.Message) {
            $content = $_.ErrorDetails.Message
        }
    }

    if ($status -ne 422) {
        throw "$label expected status 422 but got $status"
    }

    if (-not $content) {
        throw "$label missing error envelope body"
    }

    $err = $content | ConvertFrom-Json
    if (-not ($err.PSObject.Properties.Name -contains 'success')) { throw "$label missing success field" }
    if (-not ($err.PSObject.Properties.Name -contains 'ok')) { throw "$label missing ok field" }
    if (-not ($err.PSObject.Properties.Name -contains 'error')) { throw "$label missing error field" }
    if ($err.success -ne $false -or $err.ok -ne $false) { throw "$label expected success=false and ok=false" }
    if ($null -eq $err.error.code -or $err.error.code -ne 'VALIDATION_ERROR') { throw "$label expected VALIDATION_ERROR code" }
    if ($null -eq $err.error.message -or $err.error.message -eq '') { throw "$label expected validation error message" }
}

Write-Host '[Phase5-Contract] Checking success envelope on customer create'
$customer = Invoke-Json 'POST' '/api/v1/crm/customers' @{
    tenant_id = 1
    dealer_id = 2
    name = "Contract Customer $suffix"
    email = "contract.$suffix@example.com"
    phone = "9222$suffix"
    city = 'Pune'
    lifecycle_stage = 'ACTIVE'
    source = 'MANUAL'
}
Assert-SuccessEnvelope $customer 'customer create'

Write-Host '[Phase5-Contract] Checking validation error envelope on bad email'
Assert-ValidationEnvelope 'POST' '/api/v1/crm/customers' @{
    tenant_id = 1
    dealer_id = 2
    name = "Bad Email $suffix"
    email = 'bad-email'
    lifecycle_stage = 'ACTIVE'
    source = 'MANUAL'
} 'invalid email'

Write-Host '[Phase5-Contract] PASS'
