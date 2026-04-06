# Release Checklist

Date: 2026-04-04
Scope: Local-first Battery Management release readiness

## 1. Environment and Services

- Docker daemon running
- Containers healthy:
  - bm-app
  - bm-mysql
  - bm-redis
- Runtime environment file exists (.env)
- App reachable at http://127.0.0.1:8000

## 2. Database Integrity

- Run ordered migrations using scripts/run-migrations.ps1
- Confirm all migrations apply cleanly through 007_phase4_crm.sql
- Confirm baseline tenant exists (slug: default)

## 3. Quality Gates

- Run consolidated release gate:
  - scripts/phase5-gate.ps1
- Gate must pass all checks:
  - PHP lint for CRM hardening files
  - CRM contract smoke
  - Phase 5 stabilization smoke
  - Phase 4 CRM regression smoke
  - Phase 1A, 1D, Phase 2, Phase 3 regression smokes

## 4. CRM Hardening Assertions

- Invalid email payload returns 422 with structured error envelope
- Invalid channel payload returns 422 with structured error envelope
- Invalid lead backward transition rejected with 422
- Segment resolution deterministic across repeated requests
- Re-dispatch of completed campaign rejected with 422

## 5. Operational Readiness

- No syntax errors in app and public PHP files
- PHASE_STATUS.md includes Phase 5 PASS evidence and gate output
- Release command available:
  - scripts/pre-release.ps1

## 6. Release Command

Run one command:

powershell -ExecutionPolicy Bypass -File .\scripts\pre-release.ps1

Expected output:
- Pre-release checks started
- Migration pass summary
- Phase 5 gate pass summary
- PRE-RELEASE PASS
