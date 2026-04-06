# Phase Status Log

## Phase 0: Local Foundation

Date: 2026-04-04
Result: PASS

### Evidence Summary

- PASS: required setup files are present
- PASS: docker compose is available
- PASS: .env exists and runtime defaults are configured
- PASS: bm-mysql running and healthy
- PASS: bm-redis running and healthy
- PASS: Gate script output shows `Gate 0 Result: PASS`

## Phase 1A: Foundation Auth Vertical Slice

Date: 2026-04-04
Result: PASS

### Implemented

- Minimal PHP runtime entrypoint and router
- DB connection + env loader
- Identity module with:
	- POST /api/v1/auth/send-otp
	- POST /api/v1/auth/verify-otp
- Migration 001 for plans, tenants, users, otp_tokens, login_attempts, email_queue, auth_refresh_tokens
- Migration runner script and smoke test script

### Evidence Summary

- PASS: migrations applied successfully via scripts/run-migrations.ps1
- PASS: PHP syntax checks passed for all new files
- PASS: smoke test passed via scripts/phase1a-smoke.ps1

### Gate Rule

Do not move to Phase 1B until these checks remain green after any schema or auth code changes.

## Phase 1B: Claims and Batteries Vertical Slice

Date: 2026-04-04
Result: PASS

### Implemented

- Battery serial validation service with orange-tick decision logic
- Claim service with tenant-scoped claim-number sequence generation
- Claim status history write on claim creation
- New endpoints:
	- POST /api/v1/claims/check-serial
	- POST /api/v1/claims
- Migration 002 for batteries, tenant_sequences, claims, claim_status_history
- Phase 1B smoke script

### Evidence Summary

- PASS: migrations applied via scripts/run-migrations.ps1 (001 + 002)
- PASS: check-serial endpoint returns battery metadata and orange-tick state
- PASS: create-claim endpoint returns 201 and generated claim number
- PASS: scripts/phase1b-smoke.ps1 output successful claim creation

### Gate Rule

Do not move to Phase 1C until route/task/service-center schema and driver flow checks are green.

## Phase 1C: Driver and Service Vertical Slice

Date: 2026-04-04
Result: PASS

### Implemented

- Driver route creation
- Driver task assignment
- Handshake capture with dedupe hash and handshake-task pivot
- Service inward creation
- Diagnosis flow with claim status transition to READY_FOR_RETURN on OK
- Migration 003 for driver_routes, driver_tasks, driver_handshakes, handshake_tasks, service_jobs
- Phase 1C smoke script

### Evidence Summary

- PASS: migrations applied via scripts/run-migrations.ps1 (001 + 002 + 003)
- PASS: route creation returns route_id
- PASS: task assignment returns task_id
- PASS: task completion creates handshake and updates claim state
- PASS: service inward creates service_job_id
- PASS: diagnosis updates claim to READY_FOR_RETURN
- PASS: scripts/phase1c-smoke.ps1 completed successfully

### Gate Rule

Do not move to Phase 1D until auth, claims, and driver/service smoke tests remain green together after further API-layer changes.

## Phase 1D: Token Rotation and Handshake-Linked Incentives

Date: 2026-04-04
Result: PASS

### Implemented

- Signed access token issuer utility
- Refresh token rotation endpoint
- Logout endpoint with refresh-token revocation
- Refresh attempt tracking using existing login_attempts table
- Delivery incentive creation only when a delivery task is completed with a handshake
- Migration 004 for auth_refresh_tokens.last_used_at and delivery_incentives
- Phase 1D smoke script

### Endpoints Added

- POST /api/v1/auth/refresh
- POST /api/v1/auth/logout

### Evidence Summary

- PASS: migrations applied via scripts/run-migrations.ps1 (001 + 002 + 003 + 004)
- PASS: refresh endpoint rotates refresh token and returns a new access token
- PASS: logout revokes the active refresh token
- PASS: reusing a revoked refresh token returns 401
- PASS: completing DELIVERY_NEW task inserts one delivery_incentives row tied to handshake_id
- PASS: scripts/phase1d-smoke.ps1 completed successfully
- PASS: regression smoke suites remain green:
	- scripts/phase1a-smoke.ps1
	- scripts/phase1b-smoke.ps1
	- scripts/phase1c-smoke.ps1

### Gate Rule

Do not move to Phase 2 until reporting/tally work preserves the current Phase 1A-1D smoke suite as green.

## Phase 2: Reports, Tally, and Audit Depth

Date: 2026-04-04
Result: PASS

### Implemented

- Audit log table and shared audit service
- Tally import service with insert, upsert, and skip accounting
- Tally export service with CSV formula-injection guard
- Report service endpoints for:
	- lemon batteries
	- finance incentives by driver/month
	- audit summary by severity
- Migration 005 for tally_imports, tally_exports, and audit_logs
- Phase 2 smoke script

### Endpoints Added

- POST /api/v1/tally/import
- POST /api/v1/tally/export
- POST /api/v1/reports/lemon
- POST /api/v1/reports/finance
- POST /api/v1/reports/audit-summary

### Evidence Summary

- PASS: migrations applied via scripts/run-migrations.ps1 (001 + 002 + 003 + 004 + 005)
- PASS: tally import returns inserted/upserted/skipped counts
- PASS: tally export returns CSV payload with safe header/content
- PASS: lemon report returns repeated-claim batteries
- PASS: finance report returns delivery incentive aggregates
- PASS: audit summary returns severity counts from live audit rows
- PASS: scripts/phase2-smoke.ps1 completed successfully
- PASS: regression smoke suites remain green:
	- scripts/phase1a-smoke.ps1
	- scripts/phase1b-smoke.ps1
	- scripts/phase1c-smoke.ps1
	- scripts/phase1d-smoke.ps1

### Gate Rule

Do not move to Phase 3 until tenant isolation, quota enforcement, and public tracking preserve the Phase 1 and Phase 2 smoke suite as green.

## Phase 3: SaaS Controls and Public Tracking

Date: 2026-04-04
Result: PASS

### Implemented

- Router upgrade for GET routes and dynamic path params (`/api/v1/track/{token}`)
- Request object upgrade with route params and case-insensitive header access
- Plan quota guard in claim creation (`PLAN_QUOTA_EXCEEDED` with 429)
- Idempotency locking and replay for claim creation using `Idempotency-Key`
- Tracking token service:
	- token issuance on claim creation
	- token resolve endpoint
	- ticket-number lookup endpoint with IP rate limiting
- Migration 006 for:
	- tenant_settings
	- claim_tracking_tokens
	- ticket_lookup_attempts
	- api_idempotency_keys

### Endpoints Added

- GET /api/v1/track/{token}
- POST /api/v1/track/lookup

### Evidence Summary

- PASS: migrations applied via scripts/run-migrations.ps1 (001..006)
- PASS: claim create now returns tracking_url
- PASS: idempotent replay returns same claim response for same key+payload
- PASS: key reuse with quota-constrained follow-up correctly fails as expected path
- PASS: quota guard returns 429 when monthly limit exceeded
- PASS: ticket lookup returns token/tracking_url and resolve returns masked tracking payload
- PASS: invalid tracking token returns 404
- PASS: scripts/phase3-smoke.ps1 completed successfully
- PASS: regression smoke suites remain green:
	- scripts/phase1a-smoke.ps1
	- scripts/phase1b-smoke.ps1
	- scripts/phase1c-smoke.ps1
	- scripts/phase1d-smoke.ps1
	- scripts/phase2-smoke.ps1

### Gate Rule

Do not move to Phase 4 until CRM additions preserve the full smoke suite (Phase 1A through Phase 3) as green.

## Phase 4: CRM Vertical Slice

Date: 2026-04-04
Result: PASS

### Implemented

- CRM schema migration 007 for:
	- customers, leads, lead activities
	- segments, campaigns, campaign recipients, opt-outs
	- schemes, dealer targets, dealer daily sales
- CRM service and controller module:
	- customer upsert
	- lead create + stage transition with activity log
	- segment create + resolve
	- campaign create + dispatch with opt-out enforcement
	- customer opt-out endpoint
- Route registration for all Phase 4 CRM endpoints in public entrypoint
- Phase 4 smoke script covering full CRM flow

### Endpoints Added

- POST /api/v1/crm/customers
- POST /api/v1/crm/leads
- POST /api/v1/crm/leads/transition
- POST /api/v1/crm/segments
- POST /api/v1/crm/segments/resolve
- POST /api/v1/crm/campaigns
- POST /api/v1/crm/campaigns/dispatch
- POST /api/v1/crm/opt-out

### Evidence Summary

- PASS: migrations applied via scripts/run-migrations.ps1 (001..007)
- PASS: scripts/phase4-smoke.ps1 completed successfully
- PASS: lead pipeline transitions NEW -> CONTACTED -> QUALIFIED
- PASS: segment resolution returns tenant-matched recipients
- PASS: campaign dispatch completes and writes recipient rows while honoring opt-outs
- PASS: regression smoke suites remain green:
	- scripts/phase1a-smoke.ps1
	- scripts/phase1b-smoke.ps1
	- scripts/phase1c-smoke.ps1
	- scripts/phase1d-smoke.ps1
	- scripts/phase2-smoke.ps1
	- scripts/phase3-smoke.ps1

### Gate Rule

Do not move to Phase 5 until CRM stabilization tests and release hardening checks are green.

## Phase 5: Stabilization Hardening

Date: 2026-04-04
Result: PASS

### Implemented

- Input validation tightening in CRM service:
	- enum allowlists for lifecycle_stage, source, lead stage, campaign channel, opt-out channel
	- email and phone format checks for customer upsert
	- tenant ownership checks for user, customer, and segment references
	- stricter segment rule validation and safer rule-shape enforcement
- Lead transition-rule enforcement:
	- allowed state graph NEW -> CONTACTED -> QUALIFIED -> PROPOSAL -> WON/LOST
	- backward and terminal-state invalid transitions rejected with 422
- Campaign recipient determinism controls:
	- deterministic segment resolution ordering by customer id
	- dispatch allowed only from DRAFT or SCHEDULED
	- repeated dispatch attempts after completion rejected with 422
- Added Phase 5 smoke suite for hardening assertions

### Evidence Summary

- PASS: scripts/phase5-smoke.ps1 completed successfully
- PASS: invalid customer email input rejected with 422
- PASS: invalid campaign channel rejected with 422
- PASS: invalid backward lead transition rejected with 422
- PASS: segment resolve results stable across repeated calls
- PASS: second dispatch attempt on completed campaign rejected with 422
- PASS: CRM baseline regression remains green via scripts/phase4-smoke.ps1
- PASS: cross-phase regressions remain green:
	- scripts/phase1a-smoke.ps1
	- scripts/phase1d-smoke.ps1
	- scripts/phase2-smoke.ps1
	- scripts/phase3-smoke.ps1
- PASS: release-readiness additions completed:
	- scripts/phase5-contract-smoke.ps1
	- scripts/phase5-gate.ps1
	- scripts/pre-release.ps1
	- RELEASE_CHECKLIST.md
- PASS: contract envelope checks now verify `success` + `ok` + structured `error.code/message`
- PASS: full consolidated gate run shows `Phase 5 gate PASS`
- PASS: one-command pre-release run shows `PRE-RELEASE PASS`

### Gate Rule

Proceed only to release-readiness packaging and deployment hardening after preserving full smoke stability.
