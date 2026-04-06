# Phase 0: Local Setup and Gate 0

Date: 2026-04-04
Goal: Bring up a working local foundation with MySQL and Redis before module implementation.

## 1. Start Infrastructure

Use Docker Desktop or local services.

### Option A: Docker Compose

```powershell
docker compose up -d
```

Expected:
- mysql container healthy
- redis container healthy
- mailpit container running (optional local email capture)

### Option B: Native Services

- Start MySQL 8.0+
- Start Redis 7.x

## 2. Prepare Environment

```powershell
Copy-Item .env.example .env -Force
```

Update these in .env:
- DB_USER
- DB_PASS
- DB_NAME
- JWT_SECRET

## 3. Initialize Database

```powershell
# Run bootstrap SQL against local MySQL
docker exec -i bm-mysql mysql -uroot -proot < scripts/init-db.sql
```

If running native MySQL, execute scripts/init-db.sql with your MySQL client.

## 4. Migration Convention

- Place migrations in database/migrations using numeric prefix:
  - 001_init.sql
  - 002_identity.sql
  - ...
- Run in lexical order.
- Never edit an applied migration; create a new incremental migration.

## 5. Gate 0 Verification

```powershell
powershell -ExecutionPolicy Bypass -File scripts/phase0-verify.ps1
```

## 6. Gate 0 PASS Criteria

- DB connection test PASS
- Redis ping PASS
- Required folders exist PASS
- .env exists PASS
- Migration folder ready PASS

Only after all PASS: proceed to Phase 1 implementation.
