$ErrorActionPreference = 'Stop'

Write-Host "Running SQL migrations against bm-mysql..." -ForegroundColor Cyan

$files = Get-ChildItem "database/migrations/*.sql" | Sort-Object Name
if ($files.Count -eq 0) {
    Write-Host "No migration files found." -ForegroundColor Yellow
    exit 0
}

foreach ($file in $files) {
    Write-Host "Applying $($file.Name)" -ForegroundColor Gray
    Get-Content $file.FullName | docker exec -i -e MYSQL_PWD=root bm-mysql mysql -uroot -D battery_db
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Migration failed: $($file.Name)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Migrations completed." -ForegroundColor Green
exit 0
