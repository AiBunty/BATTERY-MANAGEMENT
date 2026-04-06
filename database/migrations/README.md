# Migrations

This folder contains ordered SQL migrations for the Battery Management system.

## Rules

1. Use numeric prefixes, zero-padded: 001, 002, 003...
2. One migration per logical change.
3. Never modify a migration once applied in a shared environment.
4. Use additive changes where possible.
5. Include rollback notes in comments for risky operations.

## Local Execution (example)

```powershell
Get-ChildItem database/migrations/*.sql | Sort-Object Name | ForEach-Object {
  Write-Host "Running $($_.Name)"
  Get-Content $_.FullName | docker exec -i bm-mysql mysql -uapp_user -papp_password battery_db
}
```
