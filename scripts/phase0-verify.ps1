$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Pass($msg) { Write-Host "PASS: $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red }

$failed = $false

Write-Host "Phase 0 verification started..." -ForegroundColor Cyan

# Check required files
$requiredFiles = @(
    '.env.example',
    'docker-compose.yml',
    'scripts/init-db.sql',
    'database/migrations/README.md',
    'PHASE_0_LOCAL_SETUP.md',
    'IMPLEMENTATION_PLAN.md'
)

foreach ($f in $requiredFiles) {
    if (Test-Path $f) { Pass "Found $f" } else { Fail "Missing $f"; $failed = $true }
}

# Check .env exists (optional but expected after setup)
if (Test-Path '.env') { Pass 'Found .env' } else { Fail 'Missing .env (copy from .env.example before Gate 0 sign-off)'; $failed = $true }

# Check docker compose is available
try {
    $null = docker compose version
    Pass 'docker compose available'
} catch {
    Fail 'docker compose not available'
    $failed = $true
}

# Check containers (best effort)
try {
    $containers = docker ps --format "{{.Names}}"
    if ($containers -match 'bm-mysql') { Pass 'bm-mysql running' } else { Fail 'bm-mysql not running'; $failed = $true }
    if ($containers -match 'bm-redis') { Pass 'bm-redis running' } else { Fail 'bm-redis not running'; $failed = $true }
} catch {
    Fail 'Could not check running containers'
    $failed = $true
}

# MySQL health check (query-based, exit-code driven)
$mysqlOk = $false
docker exec -e MYSQL_PWD=app_password bm-mysql sh -lc "mysql -uapp_user -D battery_db -e 'SELECT 1;'" 1>$null 2>$null
if ($LASTEXITCODE -eq 0) { $mysqlOk = $true }

if (-not $mysqlOk) {
    docker exec -e MYSQL_PWD=root bm-mysql sh -lc "mysql -uroot -e 'SELECT 1;'" 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) { $mysqlOk = $true }
}

if ($mysqlOk) {
    Pass 'MySQL connection test'
} else {
    Fail 'MySQL connection failed'
    $failed = $true
}

# Redis ping check (best effort)
try {
    $redisPing = docker exec bm-redis redis-cli ping
    if ($redisPing -match 'PONG') { Pass 'Redis ping test' } else { Fail 'Redis ping failed'; $failed = $true }
} catch {
    Fail 'Redis health check failed'
    $failed = $true
}

if ($failed) {
    Write-Host "Gate 0 Result: FAIL" -ForegroundColor Red
    exit 1
}

Write-Host "Gate 0 Result: PASS" -ForegroundColor Green
exit 0
