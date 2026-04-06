# SYSTEM_DESIGN.md
# Battery Service & Warranty Management System
**Stack:** PHP 8.2+ · MySQL 8.0+ · Redis · Vanilla JS (ES2020) / PWA · Google Maps API  
**Architecture:** Modular Monolith — API-first, Multi-tenant, SaaS-ready  
**Date:** April 2026  
**Version:** 4.1

---

## Table of Contents
1. [System Overview](#1-system-overview)
2. [Role Matrix](#2-role-matrix)
3. [Folder Structure](#3-folder-structure) — Modular Monolith
4. [Database Schema (SQL)](#4-database-schema-sql) — 52 Tables (incl. SaaS + CRM + Tracking layer)
5. [Core Business Logic](#5-core-business-logic) — 22 Sections
6. [API Route Map](#6-api-route-map) — Versioned `/api/v1/`
7. [JS: Client-Side Image Compression](#7-js-client-side-image-compression)
8. [Security Architecture](#8-security-architecture)
9. [Analytics & Reporting](#9-analytics--reporting)
10. [Deployment Notes](#10-deployment-notes)
11. [Deep Risk Register](#11-deep-risk-register--additional-vulnerabilities-found) — 22 Items
12. [SaaS Architecture & Upgrade Roadmap](#12-saas-architecture--upgrade-roadmap)
13. [CRM Module — Customer Pipeline, Campaigns & Schemes](#13-crm-module--customer-pipeline-campaigns--schemes)
14. [Public Repair Status Tracking](#14-public-repair-status-tracking)

---

## 1. System Overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│                  BROWSER / PWA / MOBILE APP                                │
│  Dealer Web  │  Driver PWA (Maps)  │  Admin Web  │  Service UI             │
│                 (Flutter / React Native — Phase 3)                         │
└────────────────────────────┬───────────────────────────────────────────────┘
                             │ HTTPS  /api/v1/* (JWT Bearer)  /web/* (Session)
┌────────────────────────────▼───────────────────────────────────────────────┐
│                  PHP 8.2+ Modular Monolith                                 │
│                                                                            │
│  Shared: TenantMiddleware ── AuthMiddleware ── RequestIdMiddleware         │
│  ↓                                                                         │
│  Modules: Identity · Tenancy · Claims · Batteries · Drivers                │
│           ServiceCenter · Inventory · Finance · Files · Notifications      │
│           Reports · Audit · **CRM** (Pipeline · Campaigns · Schemes)       │
│           **Tracking** (Public repair status — no-login token URLs)         │
│  ↓                                                                         │
│  Shared/Queue (Redis) ── Shared/Storage (Local→S3) ── EventBus            │
└────────────────────────────┬───────────────────────────────────────────────┘
                             │ PDO (Prepared Statements)
┌────────────────────────────▼──────────────────┐  ┌─────────────────────────┐
│  MySQL 8.0+                                   │  │  Redis                  │
│  Tenant-scoped (tenant_id on ALL rows)        │  │  Cache · Queue · TTL    │
└───────────────────────────────────────────────┘  └─────────────────────────┘
```

### Architecture Layers
| Layer | Technology | Responsibility |
|---|---|---|
| **HTTP** | Nginx | TLS termination, rate-limit zones, static files |
| **App** | PHP 8.2+ FPM | Modular business logic, API + web routing |
| **Auth (Web)** | PHP Sessions + CSRF | Browser admin / dealer / service panel |
| **Auth (API)** | JWT (15-min access) + opaque refresh token | Mobile app, PWA, partner integrations |
| **Queue** | Redis + workers | OTP email, notifications, reports, image jobs |
| **Cache** | Redis | Heavy report queries, tenant settings, lineage results |
| **Files** | `StorageDriver` interface | Local now → S3/R2 via single `.env` flip |
| **DB** | MySQL InnoDB | All persistent state, tenant-isolated |

### Key Design Decisions
| Decision | Current Choice | Future Upgrade Path |
|---|---|---|
| Auth | Email OTP → JWT for API / Session for web | Refresh tokens; device tracking |
| Multi-tenancy | `tenant_id` on all operational tables | Tenant-per-schema sharding if required |
| File storage | `StorageDriver` interface (Local impl) | Swap to `S3StorageDriver` via `.env` |
| Async work | Redis-backed queue workers | Scale workers independently |
| Business events | `EventBus::dispatch()` | Extract to RabbitMQ later |
| Roles | ENUM (v1 compat) → `roles/permissions` tables | Full tenant-configurable RBAC |
| Serial validation | Regex `^[A-Z0-9]{14,15}$` | Configurable via `tenant_settings` |
| Lineage | Recursive CTE + `root_battery_id` shortcut | Materialized path at very high volume |
| Tally export | CSV (semicolon-delimited) | Tenant-configurable delimiters |

---

## 2. Role Matrix

| Permission | ADMIN | SUPER_MGR | DISPATCH_MGR | DEALER | DRIVER | TESTER | INV_MGR | CRM_MGR | MARKETING |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Tally Import/Export | ✓ | ✓ | | | | | | | |
| Manage Users | ✓ | ✓ | | | | | | | |
| Settings | ✓ | | | | | | | | |
| Create Claim | | | | ✓ | | | | | |
| Edit Claim (pre-lock) | | | | ✓ | | | | | |
| View Claims | ✓ | ✓ | ✓ | Own | Assigned | | ✓ | | |
| Assign Driver Route | | | ✓ | | | | | | |
| Driver Mobile UI | | | | | ✓ | | | | |
| Inward Battery | | | | | | ✓* | ✓ | | |
| Diagnose Battery | | | | | | ✓ | | | |
| Assign Replacement | | | | | | | ✓ | | |
| Run Reports | ✓ | ✓ | ✓ | | | | | ✓ | ✓ |
| Finance Report | ✓ | ✓ | | | | | | | |
| CRM: View Pipeline | ✓ | ✓ | | Own | | | | ✓ | ✓ |
| CRM: Manage Leads | ✓ | ✓ | | | | | | ✓ | |
| CRM: Create Campaign | ✓ | | | | | | | ✓ | ✓ |
| CRM: Send Campaign | ✓ | | | | | | | ✓ | |
| CRM: Manage Schemes | ✓ | ✓ | | | | | | ✓ | |
| CRM: View Dealer Sales Graph | ✓ | ✓ | ✓ | Own | | | | ✓ | ✓ |
| CRM: Parent Scheme Config | ✓ | | | | | | | ✓ | |

*Tester performs Inwarding in simplified deployments.

---

## 3. Folder Structure

> **Modular Monolith:** each domain owns its own controllers, services, repositories, DTOs, events, and routes. Shared infrastructure lives in `app/Shared/`.

```
battery-management/
│
├── public/                               ← Web root (Nginx DocumentRoot)
│   ├── index.php                         ← Front controller
│   ├── .htaccess                         ← HTTPS redirect, CSP, HSTS, RewriteRule
│   └── assets/
│       ├── js/
│       │   ├── compress.js               ← WebP compression (§7)
│       │   ├── maps.js                   ← Google Maps driver UI
│       │   ├── scanner.js                ← Serial barcode input
│       │   ├── signature.js              ← Canvas signature pad
│       │   └── app.js                    ← Fetch wrappers, flash, request-id header
│       ├── css/app.css
│       └── uploads/                      ← Symlink → ../storage/uploads/
│           └── .htaccess                 ← Deny from all; php_flag engine off
│
├── app/
│   ├── Modules/
│   │   ├── Identity/                     ← Auth, OTP, token management
│   │   │   ├── Controllers/
│   │   │   │   ├── AuthController.php    ← OTP send/verify, logout
│   │   │   │   └── TokenController.php   ← JWT issue/refresh/revoke
│   │   │   ├── Services/
│   │   │   │   ├── AuthServiceInterface.php
│   │   │   │   ├── AuthService.php       ← OTP, rate-limit, session creation
│   │   │   │   ├── JwtService.php        ← Issue/validate JWT + refresh tokens
│   │   │   │   └── OtpService.php        ← Generate, hash, queue email
│   │   │   ├── Repositories/
│   │   │   │   ├── UserRepository.php
│   │   │   │   └── OtpTokenRepository.php
│   │   │   ├── Events/
│   │   │   │   └── UserLoggedIn.php
│   │   │   └── Routes/web.php, api.php
│   │   │
│   │   ├── Tenancy/                      ← Tenant + plan management (SaaS core)
│   │   │   ├── Controllers/TenantController.php
│   │   │   ├── Services/
│   │   │   │   ├── TenantServiceInterface.php
│   │   │   │   └── TenantService.php
│   │   │   ├── Repositories/
│   │   │   │   ├── TenantRepository.php
│   │   │   │   └── PlanRepository.php
│   │   │   └── Routes/api.php
│   │   │
│   │   ├── Claims/
│   │   │   ├── Controllers/ClaimController.php
│   │   │   ├── Services/
│   │   │   │   ├── ClaimServiceInterface.php
│   │   │   │   └── ClaimService.php      ← State machine, orange-tick, lock
│   │   │   ├── Repositories/ClaimRepository.php
│   │   │   ├── DTOs/ClaimDTO.php
│   │   │   ├── Events/
│   │   │   │   ├── ClaimCreated.php
│   │   │   │   ├── ClaimSubmitted.php
│   │   │   │   └── ClaimStatusChanged.php
│   │   │   ├── Listeners/
│   │   │   │   ├── WriteClaimStatusHistory.php
│   │   │   │   └── NotifyOnClaimChange.php
│   │   │   ├── Validators/ClaimValidator.php
│   │   │   └── Routes/web.php, api.php
│   │   │
│   │   ├── Batteries/
│   │   │   ├── Controllers/BatteryController.php
│   │   │   ├── Services/
│   │   │   │   ├── BatteryServiceInterface.php
│   │   │   │   └── BatteryService.php    ← Serial validate, MFG decode, lineage
│   │   │   ├── Repositories/BatteryRepository.php
│   │   │   ├── Validators/SerialValidator.php
│   │   │   └── Routes/api.php
│   │   │
│   │   ├── Drivers/
│   │   │   ├── Controllers/DriverController.php
│   │   │   ├── Services/
│   │   │   │   ├── DriverServiceInterface.php
│   │   │   │   └── DriverService.php     ← Route, task, handshake, EOD audit
│   │   │   ├── Repositories/
│   │   │   │   ├── DriverRouteRepository.php
│   │   │   │   └── DriverTaskRepository.php
│   │   │   ├── Events/
│   │   │   │   ├── DriverTaskCompleted.php
│   │   │   │   └── HandshakeCaptured.php
│   │   │   ├── Listeners/TriggerIncentiveOnHandshake.php
│   │   │   └── Routes/web.php, api.php
│   │   │
│   │   ├── ServiceCenter/
│   │   │   ├── Controllers/ServiceController.php
│   │   │   ├── Services/
│   │   │   │   ├── ServiceJobServiceInterface.php
│   │   │   │   └── ServiceJobService.php ← Inward, diagnose, OK path
│   │   │   ├── Repositories/ServiceJobRepository.php
│   │   │   ├── Events/
│   │   │   │   ├── BatteryInwarded.php
│   │   │   │   └── DiagnosisCompleted.php
│   │   │   └── Routes/web.php, api.php
│   │   │
│   │   ├── Inventory/
│   │   │   ├── Controllers/InventoryController.php
│   │   │   ├── Services/
│   │   │   │   ├── ReplacementServiceInterface.php
│   │   │   │   └── ReplacementService.php
│   │   │   ├── Repositories/ReplacementRepository.php
│   │   │   ├── Events/ReplacementAssigned.php
│   │   │   └── Routes/web.php, api.php
│   │   │
│   │   ├── Finance/
│   │   │   ├── Controllers/FinanceController.php
│   │   │   ├── Services/
│   │   │   │   ├── IncentiveServiceInterface.php
│   │   │   │   └── IncentiveService.php  ← Incentive gating via handshake FK
│   │   │   ├── Repositories/IncentiveRepository.php
│   │   │   ├── Events/IncentiveRecorded.php
│   │   │   └── Routes/api.php
│   │   │
│   │   ├── Files/
│   │   │   ├── Controllers/FileController.php ← Auth-gated file serve endpoint
│   │   │   ├── Services/
│   │   │   │   ├── StorageDriver.php     ← Interface (§12.5)
│   │   │   │   ├── LocalStorageDriver.php
│   │   │   │   ├── S3StorageDriver.php   ← Phase 3 (swap via .env STORAGE_DRIVER)
│   │   │   │   └── ImageService.php      ← EXIF strip, MIME validate, re-encode
│   │   │   ├── Repositories/FileRepository.php
│   │   │   └── Routes/api.php
│   │   │
│   │   ├── Notifications/
│   │   │   ├── Jobs/
│   │   │   │   ├── SendOtpEmailJob.php
│   │   │   │   └── SendNotificationJob.php
│   │   │   └── Channels/
│   │   │       ├── EmailChannel.php      ← PHPMailer
│   │   │       └── WhatsAppChannel.php   ← Phase 3
│   │   │
│   │   ├── Reports/
│   │   │   ├── Controllers/ReportController.php
│   │   │   ├── Services/
│   │   │   │   └── ReportService.php     ← Finance, Lemon, MFG failure
│   │   │   ├── Jobs/GenerateReportJob.php ← Async via queue
│   │   │   └── Routes/api.php
│   │   │
│   │   ├── Tally/
│   │   │   ├── Controllers/TallyController.php
│   │   │   ├── Services/TallyService.php ← UPSERT import, CSV export (§5.11)
│   │   │   ├── Jobs/ProcessTallyImportJob.php ← Large imports via queue
│   │   │   ├── Validators/ImportValidator.php
│   │   │   └── Routes/api.php
│   │   │
│   │   └── Audit/
│   │       ├── Services/AuditService.php ← Write audit_logs with severity
│   │       └── Listeners/
│   │           ├── AuditClaimChanges.php
│   │           └── AuditSecurityEvents.php
│   │
│   │   └── CRM/                          ← §13 — Customer Pipeline, Campaigns, Dealer Schemes
│   │       ├── Controllers/
│   │       │   ├── CustomerController.php   ← CRUD + segment membership
│   │       │   ├── LeadController.php        ← Pipeline stage management
│   │       │   ├── CampaignController.php    ← Create / dispatch / analytics
│   │       │   ├── SchemeController.php      ← Parent-company scheme CRUD + dealer targets
│   │       │   └── DealerSalesController.php ← Daily/monthly sales graph data
│   │       ├── Services/
│   │       │   ├── CrmServiceInterface.php
│   │       │   ├── CustomerService.php       ← Upsert customer from handshake/claim events
│   │       │   ├── LeadService.php           ← Pipeline state machine (§5.18)
│   │       │   ├── CampaignService.php       ← Segment resolve, channel dispatch (§5.19)
│   │       │   ├── SegmentService.php        ← JSON rule evaluator (§5.20)
│   │       │   └── SchemeService.php         ← Scheme attainment calculator (§5.21)
│   │       ├── Repositories/
│   │       │   ├── CustomerRepository.php
│   │       │   ├── LeadRepository.php
│   │       │   ├── CampaignRepository.php
│   │       │   └── SchemeRepository.php
│   │       ├── Jobs/
│   │       │   ├── DispatchCampaignBatchJob.php  ← Chunked fan-out; max 500 recipients/job
│   │       │   └── DealerSalesRollupJob.php      ← Nightly aggregate → crm_dealer_sales_daily
│   │       ├── Events/
│   │       │   ├── LeadStageChanged.php
│   │       │   ├── CampaignDispatched.php
│   │       │   └── SchemeTargetHit.php
│   │       ├── Listeners/
│   │       │   ├── AutoEnrichCustomerOnHandshake.php  ← Fires on HandshakeCaptured
│   │       │   └── AuditCampaignActions.php
│   │       └── Routes/web.php, api.php
│   │
│   ├── Tracking/                              ← Public Repair Status Tracking (§14)
│   │   ├── Controllers/
│   │   │   └── TrackingController.php         ← resolve(), lookup() — no auth
│   │   ├── Services/
│   │   │   └── TrackingService.php            ← issue(), getOrCreateToken() (§5.22)
│   │   ├── Repositories/
│   │   │   └── TrackingRepository.php
│   │   └── Routes/public.php                  ← /track/{token}, /track/lookup
│   │
│   └── Shared/
│       ├── Auth/
│       │   ├── Middleware/
│       │   │   ├── WebAuthMiddleware.php  ← Session + CSRF guard
│       │   │   ├── ApiAuthMiddleware.php  ← JWT Bearer guard
│       │   │   ├── TenantMiddleware.php   ← Resolve tenant from JWT/subdomain; inject into context
│       │   │   └── RoleMiddleware.php     ← Permission check
│       │   └── TenantContext.php          ← Thread-local tenant_id for all repository queries
│       ├── Database/
│       │   ├── Connection.php             ← PDO singleton; SET time_zone='Asia/Kolkata'
│       │   └── QueryBuilder.php           ← Thin fluent builder with tenant scope injection
│       ├── Queue/
│       │   ├── QueueDriverInterface.php
│       │   ├── RedisQueueDriver.php
│       │   └── Worker.php                 ← bin/worker.php entry point
│       ├── Events/
│       │   ├── EventBus.php               ← dispatch(Event $e): void
│       │   └── EventListenerInterface.php
│       ├── Http/
│       │   ├── Router.php
│       │   ├── Request.php
│       │   └── Response.php              ← Standardised JSON envelope (§6)
│       ├── Exceptions/
│       │   ├── ValidationException.php
│       │   ├── AuthException.php
│       │   ├── TenantException.php
│       │   └── BusinessRuleException.php
│       └── Support/
│           ├── Pagination.php
│           └── RequestId.php             ← UUID per request; logged + returned in headers
│
├── views/                                ← Web panel views (unchanged structure)
│   ├── layouts/
│   ├── auth/
│   ├── claims/
│   ├── driver/
│   ├── service/
│   ├── reports/
│   └── settings/
│
├── config/
│   ├── app.php
│   ├── database.php
│   ├── mail.php
│   ├── queue.php                         ← QUEUE_DRIVER=redis; REDIS_HOST etc.
│   ├── storage.php                       ← STORAGE_DRIVER=local|s3|r2
│   ├── jwt.php                           ← JWT_SECRET, access TTL, refresh TTL
│   └── auth.php                          ← Auth guards: web (session), api (jwt)
│
├── database/
│   └── migrations/                       ← 001–030 sequential SQL files
│
├── bin/
│   ├── worker.php                        ← Queue worker entry (run via supervisor)
│   ├── process-email-queue.php           ← Legacy cron fallback (no Redis env)
│   └── nightly-audit-reminder.php       ← Cron (midnight) EOD scan flag
│
├── storage/
│   ├── uploads/                          ← Served only via FileController
│   └── logs/app.log
│
├── tests/
│   ├── Unit/
│   │   ├── SerialValidatorTest.php
│   │   ├── BatteryLineageTest.php
│   │   ├── ClaimStateMachineTest.php
│   │   └── IncentiveGatingTest.php
│   └── Feature/
│       ├── ClaimFlowTest.php
│       ├── DriverAuditTest.php
│       ├── MultiTenancyIsolationTest.php ← CRITICAL: asserts cross-tenant data leaks are impossible
│       └── JwtAuthTest.php
│
├── vendor/
├── composer.json                         ← phpspreadsheet ^2, phpmailer ^6.8,
│                                            firebase/php-jwt ^6, predis/predis ^2
├── .env
├── .env.example
└── .gitignore
```

---

## 4. Database Schema (SQL)

> Engine: InnoDB · Charset: utf8mb4 · Collation: utf8mb4_unicode_ci

```sql
-- ============================================================
-- TABLE 1: users
-- AUTHORITATIVE SaaS schema — tenant_id on every row.
-- Role is deliberately kept as legacy_role for migration compatibility (§auth strategy below).
-- All authorization checks MUST use user_roles → roles → role_permissions.
-- ============================================================
CREATE TABLE users (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    name          VARCHAR(255)  NOT NULL,
    email         VARCHAR(255)  NOT NULL,
    phone         VARCHAR(20)   NULL,
    legacy_role   ENUM(
                    'ADMIN','DEALER','DRIVER','TESTER',
                    'INV_MANAGER','DISPATCH_MANAGER','SUPER_MANAGER'
                  ) NULL COMMENT 'DEPRECATED — migration compatibility only. Use user_roles table.',
    is_active     TINYINT(1)    NOT NULL DEFAULT 1,
    deleted_at    TIMESTAMP     NULL     COMMENT 'Soft-delete only — never hard-delete; preserves audit trail',
    deleted_by    INT UNSIGNED  NULL,
    version_no    INT UNSIGNED  NOT NULL DEFAULT 1 COMMENT 'Optimistic lock: client must match on PUT',
    created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)  REFERENCES tenants(id),
    FOREIGN KEY (deleted_by) REFERENCES users(id) ON DELETE SET NULL,
    -- Expression index (§11.21): soft-deleted rows step out of the unique envelope.
    -- When deleted_at IS NULL (live row) → key includes literal 1 → conflicts with other live rows.
    -- When deleted_at IS NOT NULL (deleted) → key includes unique id   → no conflict with new rows.
    UNIQUE KEY uq_tenant_email_live (tenant_id, email, (IF(deleted_at IS NULL, 1, id))),
    INDEX idx_tenant_active (tenant_id, is_active),
    INDEX idx_tenant_role   (tenant_id, legacy_role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 2: otp_tokens
-- ============================================================
-- SECURITY: Plaintext OTP is emailed to user; only the SHA-256 hash is stored.
-- Verify with: hash_equals(hash('sha256', $userInput), $storedHash)
-- Before inserting a new OTP, expire all prior active tokens:
--   UPDATE otp_tokens SET used=1 WHERE user_id=:uid AND used=0;
CREATE TABLE otp_tokens (
    id          INT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    user_id     INT UNSIGNED  NOT NULL,
    token_hash  CHAR(64)      NOT NULL,   -- SHA-256(plaintext_otp); plaintext NEVER persisted
    expires_at  TIMESTAMP     NOT NULL,   -- NOW() + otp_ttl_minutes (from settings)
    used        TINYINT(1)    NOT NULL DEFAULT 0,
    created_at  TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    -- token_hash is compared in PHP via hash_equals(); NOT in a SQL WHERE clause
    INDEX idx_user_active (user_id, used, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 3: settings
-- ============================================================
CREATE TABLE settings (
    `key`        VARCHAR(100) PRIMARY KEY,       -- e.g. 'delivery_incentive'
    `value`      TEXT         NOT NULL,           -- e.g. '10.00'
    description  VARCHAR(255) NULL,
    updated_by   INT UNSIGNED NULL,
    updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed defaults
INSERT INTO settings (`key`, `value`, description) VALUES
  ('delivery_incentive',      '10.00',  'INR per successful delivery'),
  ('image_quality_threshold', '0.82',   'WebP quality 0-1; also used server-side'),
  ('serial_mfg_year_pos',     '2',      '0-indexed char position for year digit'),
  ('serial_mfg_week_pos',     '3',      '0-indexed start position for week (2 chars)'),
  ('otp_ttl_minutes',         '10',     'OTP validity window in minutes');

-- ============================================================
-- TABLE 4: batteries
-- AUTHORITATIVE SaaS schema — tenant_id on every row.
-- root_battery_id / lineage_depth / replacement_count: Phase 1 lineage additions.
-- ============================================================
CREATE TABLE batteries (
    id                BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id         BIGINT UNSIGNED  NOT NULL,
    serial_number     VARCHAR(15)      NOT NULL,          -- 14-15 chars, A-Z0-9; unique per tenant
    is_in_tally       TINYINT(1)       NOT NULL DEFAULT 0, -- Populated on Tally import
    mfg_year          SMALLINT UNSIGNED NULL,             -- Decoded from serial
    mfg_week          TINYINT UNSIGNED  NULL,             -- Decoded from serial (1-53)
    model             VARCHAR(100)     NULL,
    status            ENUM(
                        'IN_STOCK','CLAIMED','IN_TRANSIT',
                        'AT_SERVICE','REPLACED','SCRAPPED'
                      ) NOT NULL DEFAULT 'IN_STOCK',
    mother_battery_id BIGINT UNSIGNED  NULL,              -- Linked-list: IMMEDIATE parent (not root). Use CTE (§5.4).
    root_battery_id   BIGINT UNSIGNED  NULL,              -- O(1) root lookup; NULL = this IS the root
    lineage_depth     SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Hop count from root (0 = original)',
    replacement_count SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'How many times replaced',
    deleted_at        TIMESTAMP        NULL,
    created_at        TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                 ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)         REFERENCES tenants(id),
    FOREIGN KEY (mother_battery_id) REFERENCES batteries(id) ON DELETE SET NULL,
    FOREIGN KEY (root_battery_id)   REFERENCES batteries(id) ON DELETE SET NULL,
    -- Expression index (§11.21): soft-deleted batteries release their serial for reuse.
    UNIQUE KEY uq_tenant_serial_live (tenant_id, serial_number, (IF(deleted_at IS NULL, 1, id))),
    INDEX idx_status        (status),
    INDEX idx_mother        (mother_battery_id),
    INDEX idx_root          (root_battery_id),
    INDEX idx_mfg           (mfg_year, mfg_week),
    INDEX idx_tally_status  (is_in_tally, status)          -- Tally UPSERT + Lemon report (§11.14)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 5: tally_imports
-- ============================================================
CREATE TABLE tally_imports (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    filename      VARCHAR(255)     NOT NULL,
    imported_by   INT UNSIGNED     NOT NULL,
    total_rows    INT UNSIGNED     NOT NULL DEFAULT 0,
    valid_rows    INT UNSIGNED     NOT NULL DEFAULT 0,
    invalid_rows  INT UNSIGNED     NOT NULL DEFAULT 0,
    inserted_rows INT UNSIGNED     NOT NULL DEFAULT 0,  -- new serials added
    upserted_rows INT UNSIGNED     NOT NULL DEFAULT 0,  -- existing serials refreshed (not CLAIMED)
    skipped_rows  INT UNSIGNED     NOT NULL DEFAULT 0,  -- CLAIMED/AT_SERVICE batteries left untouched
    imported_at   TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
    FOREIGN KEY (imported_by) REFERENCES users(id),
    INDEX idx_tenant_created  (tenant_id, imported_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 6: claims
-- AUTHORITATIVE SaaS schema — tenant_id on every row.
-- claim_number unique per tenant (not globally unique).
-- ============================================================
CREATE TABLE claims (
    id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
    tenant_id          BIGINT UNSIGNED NOT NULL,
    claim_number       VARCHAR(30)   NOT NULL,              -- e.g. ACME-CLM-2026-00001
    battery_id         BIGINT UNSIGNED NOT NULL,
    dealer_id          INT UNSIGNED  NOT NULL,
    is_orange_tick     TINYINT(1)    NOT NULL DEFAULT 0,     -- Serial not in Tally
    orange_tick_photo  VARCHAR(500)  NULL,                   -- Relative path in storage
    status             ENUM(
                         'DRAFT','SUBMITTED','DRIVER_RECEIVED',
                         'IN_TRANSIT','AT_SERVICE','DIAGNOSED',
                         'READY_FOR_RETURN',              -- diagnosis='OK'; no fault found; return to dealer
                         'REPLACED','CLOSED'
                       ) NOT NULL DEFAULT 'DRAFT',
    is_locked          TINYINT(1)    NOT NULL DEFAULT 0,     -- Set on DRIVER_RECEIVED
    customer_name      VARCHAR(255)  NULL,
    customer_phone     VARCHAR(20)   NULL,
    customer_address   TEXT          NULL,
    dealer_lat         DECIMAL(10,8) NULL,
    dealer_lng         DECIMAL(11,8) NULL,
    complaint          TEXT          NULL,
    closed_without_replacement TINYINT(1)    NOT NULL DEFAULT 0,  -- 1 when diagnosis='OK' → CLOSED directly
    created_at         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                               ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)  REFERENCES tenants(id),
    FOREIGN KEY (battery_id) REFERENCES batteries(id),
    FOREIGN KEY (dealer_id)  REFERENCES users(id),
    UNIQUE KEY uq_tenant_claim_no (tenant_id, claim_number), -- scoped: two tenants CAN share same number
    INDEX idx_tenant_dealer  (tenant_id, dealer_id),
    INDEX idx_tenant_status  (tenant_id, status),
    INDEX idx_battery        (battery_id),
    INDEX idx_dealer_status  (dealer_id, status)  -- composite: Dealer "My Claims" dashboard
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 7: driver_routes
-- ============================================================
CREATE TABLE driver_routes (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id    BIGINT UNSIGNED NOT NULL,
    driver_id    INT UNSIGNED NOT NULL,
    route_date   DATE         NOT NULL,
    status       ENUM('PLANNED','ACTIVE','COMPLETED') NOT NULL DEFAULT 'PLANNED',
    created_by   INT UNSIGNED NOT NULL,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)  REFERENCES tenants(id),
    FOREIGN KEY (driver_id)  REFERENCES users(id),
    FOREIGN KEY (created_by) REFERENCES users(id),
    UNIQUE KEY uq_tenant_driver_date (tenant_id, driver_id, route_date),
    INDEX idx_tenant_date (tenant_id, route_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 8: driver_tasks
-- ============================================================
CREATE TABLE driver_tasks (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id        BIGINT UNSIGNED NOT NULL,
    route_id         INT UNSIGNED NOT NULL,
    claim_id         BIGINT UNSIGNED NOT NULL,
    task_type        ENUM(
                       'DELIVERY_NEW',         -- New battery to dealer
                       'DELIVERY_REPLACEMENT', -- Replacement unit to dealer
                       'PICKUP_SERVICE'        -- Collect faulty battery
                     ) NOT NULL,
    status           ENUM('PENDING','ACTIVE','DONE','SKIPPED') NOT NULL DEFAULT 'PENDING',
    sequence_order   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    scanned_serial   VARCHAR(15) NULL,         -- Serial driver scanned at handshake
    skip_photo        VARCHAR(500) NULL,
    skip_reason_code  ENUM(
                        'DEALER_ABSENT','BATTERY_NOT_READY',
                        'WRONG_ADDRESS','CUSTOMER_REFUSED','OTHER'
                      ) NULL,                          -- Structured vocabulary; prevents free-text drift
    skip_reason_note  TEXT NULL,                       -- Free text; required only when code='OTHER'
    completed_at      TIMESTAMP NULL,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (route_id)  REFERENCES driver_routes(id) ON DELETE CASCADE,
    FOREIGN KEY (claim_id)  REFERENCES claims(id),
    INDEX idx_tenant_route  (tenant_id, route_id),
    INDEX idx_claim         (claim_id),
    INDEX idx_status        (status),
    INDEX idx_route_status  (route_id, status)          -- composite: Driver "Today's Tasks" view
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 9: driver_stock
-- ============================================================
-- Records every battery movement for the nightly audit equation:
-- Morning Load + Pickups - Deliveries = End-of-Day Physical
CREATE TABLE driver_stock (
    id            INT UNSIGNED   AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED NOT NULL,
    driver_id     INT UNSIGNED   NOT NULL,
    stock_date    DATE           NOT NULL,
    battery_id    BIGINT UNSIGNED NOT NULL,
    action        ENUM(
                    'MORNING_LOAD',  -- Batteries loaded at start of day
                    'DELIVERED',     -- Battery given to dealer
                    'PICKED_UP',     -- Faulty battery collected from dealer
                    'INWARD'         -- Battery handed to service centre
                  ) NOT NULL,
    task_id       INT UNSIGNED   NULL,       -- FK to driver_tasks if applicable
    created_at    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)  REFERENCES tenants(id),
    FOREIGN KEY (driver_id)  REFERENCES users(id),
    FOREIGN KEY (battery_id) REFERENCES batteries(id),
    FOREIGN KEY (task_id)    REFERENCES driver_tasks(id) ON DELETE SET NULL,
    INDEX idx_tenant_driver_date (tenant_id, driver_id, stock_date),
    INDEX idx_battery            (battery_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 10: driver_handshakes
-- sig_hash prevents recycling old signature files (§11.9).
-- client_timestamp + geo columns support forensic dispute resolution (§11.15).
-- ============================================================
CREATE TABLE driver_handshakes (
    id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id         BIGINT UNSIGNED NOT NULL,
    route_id          INT UNSIGNED NOT NULL,
    driver_id         INT UNSIGNED NOT NULL,
    dealer_id         INT UNSIGNED NOT NULL,
    batch_photo       VARCHAR(500) NOT NULL,   -- Photo of all units together
    dealer_signature  VARCHAR(500) NOT NULL,   -- Canvas PNG path
    sig_hash          CHAR(64)     NOT NULL,   -- SHA-256(signature file bytes); reject duplicates
    client_timestamp  BIGINT       NULL,       -- JS Date.now()/1000; compared vs handshake_at (§11.15)
    geo_lat           DECIMAL(10,8) NULL,      -- Driver GPS at time of handshake
    geo_lng           DECIMAL(11,8) NULL,
    handshake_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (route_id)  REFERENCES driver_routes(id),
    FOREIGN KEY (driver_id) REFERENCES users(id),
    FOREIGN KEY (dealer_id) REFERENCES users(id),
    UNIQUE KEY uq_sig_hash (sig_hash),         -- Prevent signature file reuse
    INDEX idx_tenant_driver (tenant_id, driver_id, handshake_at),
    INDEX idx_route         (route_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 11: service_jobs
-- ============================================================
CREATE TABLE service_jobs (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id       BIGINT UNSIGNED NOT NULL,
    claim_id        BIGINT UNSIGNED NOT NULL,
    inward_by       INT UNSIGNED NOT NULL,
    inward_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    assigned_tester INT UNSIGNED NULL,
    diagnosis       ENUM('PENDING','OK','REPLACE') NOT NULL DEFAULT 'PENDING',
    diagnosis_notes TEXT         NULL,
    diagnosed_at    TIMESTAMP    NULL,
    FOREIGN KEY (tenant_id)       REFERENCES tenants(id),
    FOREIGN KEY (claim_id)        REFERENCES claims(id),
    FOREIGN KEY (inward_by)       REFERENCES users(id),
    FOREIGN KEY (assigned_tester) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_tenant_diagnosis (tenant_id, diagnosis),
    INDEX idx_claim            (claim_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 12: replacements
-- ============================================================
CREATE TABLE replacements (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id       BIGINT UNSIGNED NOT NULL,
    service_job_id  INT UNSIGNED NOT NULL,
    old_battery_id  BIGINT UNSIGNED NOT NULL,
    new_battery_id  BIGINT UNSIGNED NOT NULL,
    assigned_by     INT UNSIGNED NOT NULL,
    replaced_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)      REFERENCES tenants(id),
    FOREIGN KEY (service_job_id) REFERENCES service_jobs(id),
    FOREIGN KEY (old_battery_id) REFERENCES batteries(id),
    FOREIGN KEY (new_battery_id) REFERENCES batteries(id),
    FOREIGN KEY (assigned_by)    REFERENCES users(id),
    UNIQUE KEY uq_new_battery            (new_battery_id),  -- One replacement serial used once
    INDEX idx_tenant_service_job         (tenant_id, service_job_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 13: delivery_incentives
-- ============================================================
CREATE TABLE delivery_incentives (
    id            INT UNSIGNED   AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED NOT NULL,
    driver_id     INT UNSIGNED   NOT NULL,
    task_id       INT UNSIGNED   NOT NULL UNIQUE,
    claim_id      BIGINT UNSIGNED NOT NULL,
    handshake_id  INT UNSIGNED   NOT NULL,             -- REQUIRED: incentive is forbidden without a physical handshake
    task_type     ENUM('DELIVERY_NEW','DELIVERY_REPLACEMENT') NOT NULL,  -- both task types earn incentive
    amount        DECIMAL(10,2)  NOT NULL,             -- copied from settings at time of delivery
    delivery_date DATE           NOT NULL,
    is_paid       TINYINT(1)     NOT NULL DEFAULT 0,
    paid_at       TIMESTAMP      NULL,
    FOREIGN KEY (tenant_id)    REFERENCES tenants(id),
    FOREIGN KEY (driver_id)    REFERENCES users(id),
    FOREIGN KEY (task_id)      REFERENCES driver_tasks(id),
    FOREIGN KEY (claim_id)     REFERENCES claims(id),
    FOREIGN KEY (handshake_id) REFERENCES driver_handshakes(id),
    INDEX idx_tenant_driver      (tenant_id, driver_id, is_paid),
    INDEX idx_driver_month       (driver_id, delivery_date),
    INDEX idx_incentive_paid     (driver_id, is_paid, delivery_date)   -- composite: monthly payout report
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 14: tally_exports
-- ============================================================
CREATE TABLE tally_exports (
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    exported_by    INT UNSIGNED NOT NULL,
    filename       VARCHAR(255) NOT NULL,
    total_records  INT UNSIGNED NOT NULL DEFAULT 0,
    date_from      DATE         NULL,
    date_to        DATE         NULL,
    exported_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (exported_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 15: audit_logs
-- ============================================================
CREATE TABLE audit_logs (
    id           BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id    BIGINT UNSIGNED  NOT NULL,
    request_id   CHAR(36)         NULL,      -- X-Request-ID; ties log entry to HTTP request
    user_id      INT UNSIGNED     NULL,
    action       VARCHAR(100)     NOT NULL,  -- e.g. 'claim.status_changed'
    entity_type  VARCHAR(50)      NOT NULL,  -- e.g. 'claims'
    entity_id    INT UNSIGNED     NULL,
    severity     ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL DEFAULT 'LOW',
    old_values   JSON             NULL,
    new_values   JSON             NULL,
    ip_address   VARCHAR(45)      NOT NULL,  -- IPv4 + IPv6
    user_agent   VARCHAR(500)     NULL,
    created_at   TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id)   REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_tenant_entity  (tenant_id, entity_type, entity_id),
    INDEX idx_user           (user_id),
    INDEX idx_created        (created_at),
    INDEX idx_severity       (severity)      -- Admins can filter HIGH/CRITICAL fraud alerts directly
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 16: sessions (optional — use if PHP file sessions are insufficient)
-- ============================================================
CREATE TABLE sessions (
    id            CHAR(128)    PRIMARY KEY,
    user_id       INT UNSIGNED NULL,
    ip_address    VARCHAR(45)  NOT NULL,
    user_agent    VARCHAR(500) NULL,
    payload       MEDIUMBLOB   NOT NULL,
    last_activity TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user     (user_id),
    INDEX idx_activity (last_activity)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 17: claim_status_history
-- ============================================================
-- Dedicated timeline table. Cheaper to query than JSON audit_logs for
-- "how long did a claim remain in each status?" reports.
CREATE TABLE claim_status_history (
    id          BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    claim_id    BIGINT UNSIGNED  NOT NULL,
    from_status VARCHAR(30)      NOT NULL,
    to_status   VARCHAR(30)      NOT NULL,
    changed_by  INT UNSIGNED     NOT NULL,
    changed_at  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (claim_id)   REFERENCES claims(id) ON DELETE CASCADE,
    FOREIGN KEY (changed_by) REFERENCES users(id),
    INDEX idx_claim   (claim_id),
    INDEX idx_changed (changed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 18: claim_sequences
-- ============================================================
-- Serialised counter per year-prefix; row locked with SELECT … FOR UPDATE
-- before increment to prevent CLM-number collisions under concurrent load (§5.8).
CREATE TABLE claim_sequences (
    prefix    CHAR(9)       PRIMARY KEY,    -- e.g. 'CLM-2026-'
    last_val  INT UNSIGNED  NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO claim_sequences (prefix) VALUES ('CLM-2026-');

-- ============================================================
-- TABLE 19: login_attempts
-- ============================================================
-- Multi-dimensional rate-limiting: per identifier, per IP, per tenant, and globally.
-- attempt_type distinguishes OTP send abuse from verify abuse from token refresh abuse.
CREATE TABLE login_attempts (
    id                 INT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id          BIGINT UNSIGNED NULL,              -- NULL during public pre-auth flows
    user_id            INT UNSIGNED  NULL,                -- NULL until identity confirmed
    identifier         VARCHAR(255)  NOT NULL,            -- email or phone (pre-auth key)
    ip_address         VARCHAR(45)   NOT NULL,
    device_fingerprint VARCHAR(128)  NULL,                -- browser/app fingerprint hash
    attempt_type       ENUM(
                         'SEND_OTP',
                         'VERIFY_OTP',
                         'REFRESH_TOKEN'
                       ) NOT NULL DEFAULT 'VERIFY_OTP',
    success            TINYINT(1)    NOT NULL DEFAULT 0,
    attempted_at       TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id)   REFERENCES users(id)   ON DELETE CASCADE,
    INDEX idx_identifier_window (identifier, attempted_at),  -- per-email lockout
    INDEX idx_ip_window         (ip_address, attempted_at),  -- per-IP lockout
    INDEX idx_tenant_window     (tenant_id, attempted_at)    -- per-tenant burst detection
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 20: email_queue
-- ============================================================
-- OTP emails are NEVER sent synchronously during an HTTP request.
-- bin/process-email-queue.php (cron every minute) drains this table.
CREATE TABLE email_queue (
    id           INT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id    BIGINT UNSIGNED NOT NULL,
    recipient    VARCHAR(255)  NOT NULL,
    subject      VARCHAR(255)  NOT NULL,
    body         TEXT          NOT NULL,
    status       ENUM('PENDING','SENT','FAILED') NOT NULL DEFAULT 'PENDING',
    attempts     TINYINT       NOT NULL DEFAULT 0,   -- max 3 before FAILED
    last_attempt TIMESTAMP     NULL,
    sent_at      TIMESTAMP     NULL,
    created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    INDEX idx_tenant_pending (tenant_id, status, attempts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 21: driver_eod_audits
-- ============================================================
-- Persists each driver's nightly stock verification for historical reporting.
-- Corrected equation: expected_eod = morning_load + picked_up - delivered - inwarded (§5.5)
CREATE TABLE driver_eod_audits (
    id            INT UNSIGNED       AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED    NOT NULL,
    driver_id     INT UNSIGNED       NOT NULL,
    audit_date    DATE               NOT NULL,
    morning_load  SMALLINT UNSIGNED  NOT NULL DEFAULT 0,
    picked_up     SMALLINT UNSIGNED  NOT NULL DEFAULT 0,
    delivered     SMALLINT UNSIGNED  NOT NULL DEFAULT 0,
    inwarded      SMALLINT UNSIGNED  NOT NULL DEFAULT 0,  -- batteries handed to service centre
    expected_eod  SMALLINT UNSIGNED  NOT NULL DEFAULT 0,  -- morning_load + picked_up - delivered - inwarded
    physical_scan SMALLINT UNSIGNED  NOT NULL DEFAULT 0,
    discrepancy   SMALLINT           NOT NULL DEFAULT 0,  -- physical_scan - expected_eod (negative = missing)
    is_balanced   TINYINT(1)         NOT NULL DEFAULT 0,
    notes         TEXT               NULL,
    created_at    TIMESTAMP          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (driver_id) REFERENCES users(id),
    UNIQUE KEY uq_tenant_driver_date (tenant_id, driver_id, audit_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### SaaS Tables (Phase 1 additions — TABLE 22–38)

```sql
-- TABLE 22: tenants
-- One row per customer organisation; all operational data is scoped by tenant_id.
CREATE TABLE tenants (
    id          BIGINT UNSIGNED    AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(120)       NOT NULL,
    slug        VARCHAR(60)        NOT NULL UNIQUE,          -- subdomain key e.g. "acme"
    plan_id     BIGINT UNSIGNED    NOT NULL,
    is_active   TINYINT(1)         NOT NULL DEFAULT 1,
    timezone    VARCHAR(60)        NOT NULL DEFAULT 'Asia/Kolkata',
    created_at  TIMESTAMP          NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP          NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (plan_id) REFERENCES plans(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- TABLE 23: plans
CREATE TABLE plans (
    id              BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(60)      NOT NULL,               -- "starter", "business", "enterprise"
    max_users       SMALLINT         NOT NULL DEFAULT 10,
    max_monthly_claims INT           NOT NULL DEFAULT 500,
    features_json   JSON             NULL,                   -- {"reports":true,"api":true}
    price_monthly   DECIMAL(10,2)    NOT NULL DEFAULT 0.00,
    is_active       TINYINT(1)       NOT NULL DEFAULT 1,
    created_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- TABLE 24: roles  (replaces ENUM role on users — backward-compatible migration)
CREATE TABLE roles (
    id          BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id   BIGINT UNSIGNED  NOT NULL,
    name        VARCHAR(60)      NOT NULL,                   -- admin, manager, driver, service_agent, dealer
    description VARCHAR(255)     NULL,
    is_system   TINYINT(1)       NOT NULL DEFAULT 0,         -- 1 = cannot be deleted
    created_at  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    UNIQUE KEY uq_tenant_role (tenant_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- TABLE 25: permissions
CREATE TABLE permissions (
    id          BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(100)     NOT NULL UNIQUE,            -- "claims.create", "reports.finance.view"
    module      VARCHAR(60)      NOT NULL,
    description VARCHAR(255)     NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- TABLE 26: role_permissions
CREATE TABLE role_permissions (
    role_id       BIGINT UNSIGNED  NOT NULL,
    permission_id BIGINT UNSIGNED  NOT NULL,
    PRIMARY KEY (role_id, permission_id),
    FOREIGN KEY (role_id)       REFERENCES roles(id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- TABLE 27: user_roles
CREATE TABLE user_roles (
    user_id     INT UNSIGNED     NOT NULL,
    role_id     BIGINT UNSIGNED  NOT NULL,
    granted_by  INT UNSIGNED     NULL,
    granted_at  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (user_id)    REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (role_id)    REFERENCES roles(id) ON DELETE CASCADE,
    FOREIGN KEY (granted_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- TABLE 28: files  (StorageDriver abstraction — all uploads tracked here)
CREATE TABLE files (
    id                 BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id          BIGINT UNSIGNED  NOT NULL,
    uploaded_by        INT UNSIGNED     NOT NULL,
    entity_type        VARCHAR(60)      NOT NULL,            -- "claim", "handshake", "tally"
    entity_id          BIGINT UNSIGNED  NOT NULL,
    storage_driver     VARCHAR(20)      NOT NULL DEFAULT 'local', -- 'local', 's3', 'r2'
    disk_path          VARCHAR(512)     NOT NULL,            -- relative key on that driver
    mime_type          VARCHAR(100)     NOT NULL,
    file_size_kb       INT UNSIGNED     NOT NULL DEFAULT 0,
    original_name      VARCHAR(255)     NOT NULL,
    checksum_sha256    CHAR(64)         NULL,                -- SHA-256 of stored bytes; verify on serve
    virus_scan_status  ENUM('PENDING','CLEAN','INFECTED','SKIPPED') NOT NULL DEFAULT 'PENDING',
    virus_scanned_at   TIMESTAMP        NULL,
    quarantined_at     TIMESTAMP        NULL,                -- Set if virus_scan_status = INFECTED
    encryption_key_id  VARCHAR(128)     NULL,                -- KMS key reference (Phase 3)
    deleted_at         TIMESTAMP        NULL,                -- Soft-delete
    deleted_by         INT UNSIGNED     NULL,
    created_at         TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
    FOREIGN KEY (uploaded_by) REFERENCES users(id),
    FOREIGN KEY (deleted_by)  REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_entity      (tenant_id, entity_type, entity_id),
    INDEX idx_scan_status (virus_scan_status, virus_scanned_at)  -- worker processes PENDING queue
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- TABLE 29: tenant_settings  (per-tenant overrides; replaces global settings for SaaS)
CREATE TABLE tenant_settings (
    id          BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id   BIGINT UNSIGNED  NOT NULL,
    key         VARCHAR(100)     NOT NULL,
    value       TEXT             NOT NULL,
    updated_at  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    UNIQUE KEY uq_tenant_key (tenant_id, `key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- TABLE 30: tenant_sequences  (replaces claim_sequences; race-free CLM# per tenant — §5.10)
CREATE TABLE tenant_sequences (
    tenant_id   BIGINT UNSIGNED  NOT NULL,
    seq_name    VARCHAR(60)      NOT NULL,                   -- "CLM", "SRV", "DRV"
    current_val BIGINT UNSIGNED  NOT NULL DEFAULT 0,
    prefix      VARCHAR(10)      NOT NULL DEFAULT '',
    reset_cycle ENUM('never','daily','monthly','yearly') NOT NULL DEFAULT 'never',
    PRIMARY KEY (tenant_id, seq_name),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 31: auth_refresh_tokens
-- Stores opaque refresh-token stubs (hashed). Access tokens are short-lived
-- (15 min JWT); refresh tokens survive 30 days and are invalidated on use
-- (rotation) or explicit logout. device_id links to auth_devices (TABLE 35).
-- ============================================================
CREATE TABLE auth_refresh_tokens (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    user_id       INT UNSIGNED     NOT NULL,
    token_hash    CHAR(64)         NOT NULL,   -- SHA-256(opaque token); plaintext never stored
    device_id     VARCHAR(128)     NULL,        -- FK to auth_devices.device_id (logical, no hard FK)
    device_name   VARCHAR(255)     NULL,
    ip_address    VARCHAR(45)      NOT NULL,
    user_agent    VARCHAR(500)     NULL,
    expires_at    TIMESTAMP        NOT NULL,
    revoked_at    TIMESTAMP        NULL,        -- Set on logout / rotation invalidation
    last_used_at  TIMESTAMP        NULL,
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id)   REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uq_token_hash  (token_hash),
    INDEX idx_user_active     (tenant_id, user_id, revoked_at, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 32: handshake_tasks  (pivot: closes handshake ↔ task fraud gap §11.9)
-- IncentiveService MUST JOIN through this table to confirm which specific
-- task was covered by a given handshake. Without this pivot any handshake_id
-- FK on delivery_incentives is not fully provable.
-- ============================================================
CREATE TABLE handshake_tasks (
    handshake_id  INT UNSIGNED  NOT NULL,
    task_id       INT UNSIGNED  NOT NULL,
    PRIMARY KEY (handshake_id, task_id),
    UNIQUE KEY uq_task_once (task_id),          -- one task in exactly one handshake
    FOREIGN KEY (handshake_id) REFERENCES driver_handshakes(id) ON DELETE CASCADE,
    FOREIGN KEY (task_id)      REFERENCES driver_tasks(id)      ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 33: outbox_events  (transactional-outbox pattern for EventBus)
-- EventBus::dispatch() writes to this table INSIDE the business transaction.
-- A separate Supervisor worker polls PENDING rows and publishes to Redis/queue.
-- Guarantees "at-least-once" delivery without dual-write risk.
-- ============================================================
CREATE TABLE outbox_events (
    id              BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id       BIGINT UNSIGNED  NOT NULL,
    event_uuid      CHAR(36)         NOT NULL DEFAULT (UUID()),  -- guaranteed globally unique; used for consumer dedupe
    event_name      VARCHAR(100)     NOT NULL,   -- e.g. "claim.submitted"
    aggregate_type  VARCHAR(50)      NOT NULL,   -- e.g. "claims"
    aggregate_id    BIGINT UNSIGNED  NOT NULL,
    payload         JSON             NOT NULL,
    status          ENUM('PENDING','PUBLISHED','FAILED') NOT NULL DEFAULT 'PENDING',
    available_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    published_at    TIMESTAMP        NULL,
    created_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    UNIQUE KEY uq_event_uuid  (event_uuid),      -- prevents accidental duplicate dispatch
    INDEX idx_publish         (status, available_at)  -- worker SELECT … WHERE status='PENDING'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 36: processed_events  (consumer-side idempotency / dedupe)
-- Before processing an outbox event, each consumer checks this table.
-- If (event_uuid, consumer_name) already exists → skip (already processed).
-- Insert atomically AFTER successful processing to mark completion.
-- Guarantees exactly-once processing per consumer despite at-least-once delivery.
-- ============================================================
CREATE TABLE processed_events (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    event_uuid    CHAR(36)         NOT NULL,
    consumer_name VARCHAR(100)     NOT NULL,   -- e.g. "IncentiveListener", "NotificationWorker"
    processed_at  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_event_consumer (event_uuid, consumer_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 37: tenant_usage_daily  (usage metering — one row per tenant per day)
-- Incremented by domain event listeners (claim.submitted, user.logged_in, file.uploaded).
-- Plan quota checks compare against this table; billing aggregates from it.
-- ============================================================
CREATE TABLE tenant_usage_daily (
    id             BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id      BIGINT UNSIGNED  NOT NULL,
    usage_date     DATE             NOT NULL,
    claims_created INT UNSIGNED     NOT NULL DEFAULT 0,
    active_users   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    storage_bytes  BIGINT UNSIGNED  NOT NULL DEFAULT 0,
    api_calls      INT UNSIGNED     NOT NULL DEFAULT 0,
    report_exports SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    UNIQUE KEY uq_tenant_day (tenant_id, usage_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 38: tenant_usage_monthly  (pre-aggregated monthly rollup for billing)
-- Populated nightly by a cron job that SUMs the daily rows for the closing month.
-- ============================================================
CREATE TABLE tenant_usage_monthly (
    id              BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id       BIGINT UNSIGNED  NOT NULL,
    usage_month     CHAR(7)          NOT NULL,  -- "YYYY-MM"
    claims_created  INT UNSIGNED     NOT NULL DEFAULT 0,
    peak_active_users SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    total_storage_bytes BIGINT UNSIGNED NOT NULL DEFAULT 0,
    api_calls       INT UNSIGNED     NOT NULL DEFAULT 0,
    report_exports  SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    plan_limit_hits INT UNSIGNED     NOT NULL DEFAULT 0,  -- times PlanGuard returned 429
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    UNIQUE KEY uq_tenant_month (tenant_id, usage_month)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 34: api_idempotency_keys
-- Stores the response for critical POST endpoints for 24 hours.
-- Middleware checks this before executing handlers; re-plays cached response
-- on replay without re-running business logic. Prevents duplicate claims,
-- duplicate incentives, duplicate handshakes (§5.16).
--
-- IN-FLIGHT LOCKING (§11.17 — race condition fix):
--   Middleware first does a single atomic INSERT with status='PROCESSING'.
--   Any concurrent duplicate request hits the UNIQUE KEY and receives 409 immediately.
--   On handler completion, UPDATE status='COMPLETE', set response_code + response_body.
--
-- CONFLICT POLICY (enforced by IdempotencyMiddleware):
--   • Same key + SAME request_hash   → replay cached response (200/201 as stored)
--   • Same key + DIFFERENT hash      → reject 409 Conflict ("idempotency_key_mismatch")
--
-- Canonical hash: SHA-256( strtoupper(method) . normalised_route . stable_json_encode(body) . tenant_id . user_id )
--   - stable_json_encode = keys alphabetically sorted, no whitespace
--   - normalised_route   = path without query string, lowercase
-- ============================================================
CREATE TABLE api_idempotency_keys (
    id                BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id         BIGINT UNSIGNED  NOT NULL,
    user_id           INT UNSIGNED     NOT NULL,
    idempotency_key   VARCHAR(128)     NOT NULL,   -- UUID v4 sent by client
    request_hash      CHAR(64)         NOT NULL,   -- SHA-256(method+path+body)
    status            ENUM('PROCESSING','COMPLETE') NOT NULL DEFAULT 'PROCESSING', -- in-flight lock (§11.17)
    response_code     SMALLINT         NULL,       -- NULL while status='PROCESSING'
    response_body     JSON             NULL,       -- NULL while status='PROCESSING'
    expires_at        TIMESTAMP        NOT NULL,   -- NOW() + 24h
    created_at        TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id)   REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uq_key (tenant_id, user_id, idempotency_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 35: auth_devices
-- Tracks registered mobile/PWA devices per user. Enables per-device session
-- revocation, push notifications, and offline sync conflict detection (§12.5).
-- ============================================================
CREATE TABLE auth_devices (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    user_id       INT UNSIGNED     NOT NULL,
    device_id     VARCHAR(128)     NOT NULL,    -- app-generated UUID, stable across app re-installs
    platform      VARCHAR(50)      NOT NULL,    -- "android", "ios", "pwa"
    app_version   VARCHAR(50)      NULL,
    push_token    VARCHAR(255)     NULL,        -- FCM/APNS token for push notifications
    last_seen_at  TIMESTAMP        NULL,
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id)   REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uq_user_device (tenant_id, user_id, device_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### ALTER TABLE for SaaS Migration — tenant_id

Add `tenant_id` to all operational tables. Pattern (shown for `claims`; repeat for all 18 tables below):

```sql
ALTER TABLE claims
  ADD COLUMN tenant_id BIGINT UNSIGNED NOT NULL AFTER id,
  ADD INDEX idx_tenant_status  (tenant_id, status),
  ADD INDEX idx_tenant_created (tenant_id, created_at),
  ADD CONSTRAINT fk_claims_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id);
```

**Tables requiring `tenant_id` (18 total):**

| # | Table | Extra index beyond `(tenant_id, ...)` |
|---|-------|---------------------------------------|
| 1 | `users` | `(tenant_id, role, is_active)` |
| 2 | `settings` | → Superseded by `tenant_settings` (keep for fallback) |
| 3 | `batteries` | `(tenant_id, serial_number)` UNIQUE |
| 4 | `claims` | `(tenant_id, status)`, `(tenant_id, dealer_id)` |
| 5 | `driver_routes` | `(tenant_id, driver_id, route_date)` |
| 6 | `driver_tasks` | `(tenant_id, route_id, status)` |
| 7 | `driver_stock` | `(tenant_id, driver_id, stock_date)` |
| 8 | `driver_handshakes` | `(tenant_id, driver_id, handshake_at)` |
| 9 | `service_jobs` | `(tenant_id, diagnosis)` |
| 10 | `replacements` | `(tenant_id, service_job_id)` |
| 11 | `delivery_incentives` | `(tenant_id, driver_id, is_paid)` |
| 12 | `tally_imports` | `(tenant_id, created_at)` |
| 13 | `tally_exports` | `(tenant_id, created_at)` |
| 14 | `claim_status_history` | `(tenant_id, claim_id, changed_at)` |
| 15 | `login_attempts` | `(tenant_id, identifier)` |
| 16 | `email_queue` | `(tenant_id, status)` |
| 17 | `audit_logs` | `(tenant_id, entity_type, entity_id)` |
| 18 | `driver_eod_audits` | `(tenant_id, driver_id, audit_date)` |

### Additional Columns — Batteries Lineage (Phase 1)

```sql
ALTER TABLE batteries
  ADD COLUMN root_battery_id   BIGINT UNSIGNED NULL     COMMENT 'NULL for root; points to the original battery',
  ADD COLUMN lineage_depth     SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Hop count from root (0 = original)',
  ADD COLUMN replacement_count SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'How many times this battery has been replaced',
  ADD COLUMN tenant_id         BIGINT UNSIGNED NOT NULL AFTER id,
  ADD INDEX  idx_root (root_battery_id),
  ADD UNIQUE KEY uq_tenant_serial (tenant_id, serial_number);
-- NOTE: mother_battery_id (TABLE 4) retains the direct-parent FK (linked list).
--       root_battery_id enables O(1) root lookup without walking the chain (§5.2 lineage CTE).
```

---

### CRM Tables (Phase 2 additions — TABLE 39–50)

> All CRM tables carry `tenant_id` and are multi-tenant-safe.  
> `crm_customers` is the canonical customer record, auto-enriched from handshake/claim events.  
> Channel opt-out is enforced in `crm_opt_outs` — checked before every campaign dispatch.

```sql
-- ============================================================
-- TABLE 39: crm_customers
-- Canonical, deduplicated customer profiles. One row per real-world
-- end customer. Auto-upserted when a HandshakeCaptured event fires
-- (§5.19). Dealer staff can also add customers manually.
-- ============================================================
CREATE TABLE crm_customers (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    dealer_id     INT UNSIGNED     NOT NULL              COMMENT 'FK users.id WHERE legacy_role=DEALER',
    name          VARCHAR(255)     NOT NULL,
    phone         VARCHAR(20)      NOT NULL,
    email         VARCHAR(255)     NULL,
    address       TEXT             NULL,
    city          VARCHAR(100)     NULL,
    state         VARCHAR(100)     NULL,
    pincode       VARCHAR(10)      NULL,
    source        ENUM('HANDSHAKE','MANUAL','IMPORT','API') NOT NULL DEFAULT 'HANDSHAKE',
    lifecycle_stage ENUM('LEAD','PROSPECT','ACTIVE','REPEAT','CHURNED') NOT NULL DEFAULT 'LEAD',
    total_batteries_bought SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    last_purchase_at TIMESTAMP    NULL,
    notes         TEXT             NULL,
    deleted_at    TIMESTAMP        NULL,
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)  REFERENCES tenants(id),
    FOREIGN KEY (dealer_id)  REFERENCES users(id),
    UNIQUE KEY uq_tenant_phone_live (tenant_id, phone, (IF(deleted_at IS NULL, 1, id))),
    INDEX idx_tenant_dealer    (tenant_id, dealer_id),
    INDEX idx_tenant_lifecycle (tenant_id, lifecycle_stage),
    INDEX idx_tenant_city      (tenant_id, city)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 40: crm_leads
-- Pipeline opportunities tracked per customer. A customer may have
-- multiple active leads (e.g., one for each new battery model enquiry).
-- Lifecycle: NEW → CONTACTED → QUALIFIED → PROPOSAL → WON | LOST
-- ============================================================
CREATE TABLE crm_leads (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    customer_id   BIGINT UNSIGNED  NOT NULL,
    assigned_to   INT UNSIGNED     NULL                  COMMENT 'FK users.id — sales rep / dealer',
    title         VARCHAR(255)     NOT NULL              COMMENT 'Short description e.g. "2Ah AGM Replacement"',
    stage         ENUM('NEW','CONTACTED','QUALIFIED','PROPOSAL','WON','LOST') NOT NULL DEFAULT 'NEW',
    expected_value DECIMAL(10,2)   NULL                  COMMENT 'INR estimated deal value',
    expected_close_date DATE       NULL,
    lost_reason   VARCHAR(255)     NULL,
    source        VARCHAR(100)     NULL                  COMMENT 'walk-in, whatsapp, campaign, referral…',
    follow_up_at  TIMESTAMP        NULL,
    closed_at     TIMESTAMP        NULL,
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
    FOREIGN KEY (customer_id) REFERENCES crm_customers(id),
    FOREIGN KEY (assigned_to) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_tenant_stage     (tenant_id, stage),
    INDEX idx_tenant_assigned  (tenant_id, assigned_to),
    INDEX idx_follow_up        (tenant_id, follow_up_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 41: crm_lead_activities
-- Append-only timeline log per lead: calls, WhatsApp messages,
-- site visits, internal notes.
-- ============================================================
CREATE TABLE crm_lead_activities (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    lead_id       BIGINT UNSIGNED  NOT NULL,
    user_id       INT UNSIGNED     NOT NULL              COMMENT 'Who logged the activity',
    activity_type ENUM('NOTE','CALL','EMAIL','WHATSAPP','VISIT','STAGE_CHANGE','FOLLOW_UP') NOT NULL,
    body          TEXT             NULL,
    old_stage     VARCHAR(50)      NULL,                 -- populated on STAGE_CHANGE
    new_stage     VARCHAR(50)      NULL,
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (lead_id)   REFERENCES crm_leads(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id)   REFERENCES users(id),
    INDEX idx_lead_created (lead_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 42: crm_message_templates
-- Reusable message templates for email and WhatsApp campaigns.
-- Placeholders: {{customer_name}}, {{dealer_name}}, {{offer_details}},
--               {{scheme_name}}, {{valid_until}}, {{cta_link}}
-- ============================================================
CREATE TABLE crm_message_templates (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    name          VARCHAR(255)     NOT NULL,
    channel       ENUM('EMAIL','WHATSAPP','BOTH') NOT NULL,
    subject       VARCHAR(500)     NULL                  COMMENT 'Email subject line; NULL for WA',
    body_html     LONGTEXT         NULL                  COMMENT 'HTML content for email',
    body_text     TEXT             NOT NULL              COMMENT 'Plain-text / WA message body',
    -- SECURITY: body fields are stored raw; rendered via twig-sandbox with only
    -- allow-listed variables. Never eval() or extract() template variables.
    is_active     TINYINT(1)       NOT NULL DEFAULT 1,
    created_by    INT UNSIGNED     NULL,
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)  REFERENCES tenants(id),
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_tenant_channel (tenant_id, channel, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 43: crm_segments
-- Saved audience segments defined as JSON rule sets.
-- SegmentService resolves a segment to a list of crm_customer IDs
-- at dispatch time — always uses fresh DB snapshot (no cached list).
-- Rule schema: { "operator": "AND", "conditions": [
--   { "field": "lifecycle_stage", "op": "eq",  "value": "ACTIVE" },
--   { "field": "city",            "op": "eq",  "value": "Mumbai" },
--   { "field": "total_batteries_bought", "op": "gte", "value": 2 }
-- ]}
-- Allowed fields whitelist enforced in SegmentService::resolveCondition()
-- to prevent SQL injection through field names.
-- ============================================================
CREATE TABLE crm_segments (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    name          VARCHAR(255)     NOT NULL,
    description   TEXT             NULL,
    rules         JSON             NOT NULL,
    estimated_count INT UNSIGNED   NULL                  COMMENT 'Cached from last resolve; informational only',
    last_resolved_at TIMESTAMP     NULL,
    created_by    INT UNSIGNED     NULL,
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)  REFERENCES tenants(id),
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_tenant (tenant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 44: crm_campaigns
-- One campaign = one outbound communication blast (email or WA or both).
-- A campaign is linked to a segment OR an explicit customer list.
-- Status: DRAFT → SCHEDULED → DISPATCHING → COMPLETED | CANCELLED
-- ============================================================
CREATE TABLE crm_campaigns (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    name          VARCHAR(255)     NOT NULL,
    channel       ENUM('EMAIL','WHATSAPP','BOTH') NOT NULL,
    template_id   BIGINT UNSIGNED  NOT NULL,
    segment_id    BIGINT UNSIGNED  NULL                  COMMENT 'NULL if explicit recipient list',
    scheme_id     BIGINT UNSIGNED  NULL                  COMMENT 'FK crm_schemes — attach offer',
    status        ENUM('DRAFT','SCHEDULED','DISPATCHING','COMPLETED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
    scheduled_at  TIMESTAMP        NULL                  COMMENT 'NULL = send immediately on dispatch',
    dispatched_at TIMESTAMP        NULL,
    completed_at  TIMESTAMP        NULL,
    total_recipients INT UNSIGNED  NOT NULL DEFAULT 0,
    sent_count    INT UNSIGNED     NOT NULL DEFAULT 0,
    delivered_count INT UNSIGNED   NOT NULL DEFAULT 0,
    opened_count  INT UNSIGNED     NOT NULL DEFAULT 0,
    clicked_count INT UNSIGNED     NOT NULL DEFAULT 0,
    failed_count  INT UNSIGNED     NOT NULL DEFAULT 0,
    created_by    INT UNSIGNED     NULL,
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)    REFERENCES tenants(id),
    FOREIGN KEY (template_id)  REFERENCES crm_message_templates(id),
    FOREIGN KEY (segment_id)   REFERENCES crm_segments(id) ON DELETE SET NULL,
    FOREIGN KEY (created_by)   REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_tenant_status    (tenant_id, status),
    INDEX idx_tenant_scheduled (tenant_id, scheduled_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 45: crm_campaign_recipients
-- One row per customer per campaign. Populated atomically when campaign
-- transitions DRAFT → DISPATCHING to avoid runtime segment-drift.
-- ============================================================
CREATE TABLE crm_campaign_recipients (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    campaign_id   BIGINT UNSIGNED  NOT NULL,
    customer_id   BIGINT UNSIGNED  NOT NULL,
    channel       ENUM('EMAIL','WHATSAPP') NOT NULL,
    address       VARCHAR(255)     NOT NULL              COMMENT 'Email or E.164 phone number',
    status        ENUM('PENDING','SENT','DELIVERED','OPENED','CLICKED','FAILED','OPTED_OUT') NOT NULL DEFAULT 'PENDING',
    failure_reason VARCHAR(255)    NULL,
    sent_at       TIMESTAMP        NULL,
    delivered_at  TIMESTAMP        NULL,
    opened_at     TIMESTAMP        NULL,
    clicked_at    TIMESTAMP        NULL,
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
    FOREIGN KEY (campaign_id) REFERENCES crm_campaigns(id) ON DELETE CASCADE,
    FOREIGN KEY (customer_id) REFERENCES crm_customers(id),
    UNIQUE KEY uq_campaign_customer_channel (campaign_id, customer_id, channel),
    INDEX idx_campaign_status (campaign_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 46: crm_opt_outs
-- Customers who have opted out of a specific channel.
-- CHECKED before every campaign dispatch — never message an opted-out customer.
-- ============================================================
CREATE TABLE crm_opt_outs (
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    customer_id   BIGINT UNSIGNED  NOT NULL,
    channel       ENUM('EMAIL','WHATSAPP','ALL') NOT NULL,
    opted_out_at  TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reason        VARCHAR(255)     NULL,
    opted_out_by  INT UNSIGNED     NULL                  COMMENT 'NULL = self-service via unsubscribe link',
    FOREIGN KEY (tenant_id)    REFERENCES tenants(id),
    FOREIGN KEY (customer_id)  REFERENCES crm_customers(id) ON DELETE CASCADE,
    FOREIGN KEY (opted_out_by) REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE KEY uq_customer_channel (tenant_id, customer_id, channel),
    INDEX idx_tenant_customer (tenant_id, customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 47: crm_schemes
-- Parent-company marketing schemes that are pushed down to dealers.
-- A scheme can define a discount, cashback, volume incentive, or offer bundle.
-- Dealers see applicable schemes on their dashboard; CRM campaigns can
-- attach a scheme_id to communicate offer details to customers.
-- ============================================================
CREATE TABLE crm_schemes (
    id              BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id       BIGINT UNSIGNED  NOT NULL,
    name            VARCHAR(255)     NOT NULL,
    scheme_code     VARCHAR(50)      NOT NULL,
    type            ENUM('DISCOUNT','CASHBACK','VOLUME_INCENTIVE','COMBO_OFFER','LOYALTY') NOT NULL,
    description     TEXT             NULL,
    discount_pct    DECIMAL(5,2)     NULL                COMMENT 'Percentage off, e.g. 10.00 = 10%',
    cashback_amount DECIMAL(10,2)    NULL                COMMENT 'Fixed INR cashback per unit',
    min_purchase_qty SMALLINT UNSIGNED NULL              COMMENT 'Minimum units for volume incentive',
    target_role     ENUM('DEALER','DRIVER','ALL')        NOT NULL DEFAULT 'DEALER',
    valid_from      DATE             NOT NULL,
    valid_to        DATE             NOT NULL,
    is_active       TINYINT(1)       NOT NULL DEFAULT 1,
    banner_file_id  BIGINT UNSIGNED  NULL                COMMENT 'FK files — promotional banner image',
    terms_text      TEXT             NULL,
    created_by      INT UNSIGNED     NULL,
    created_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)      REFERENCES tenants(id),
    FOREIGN KEY (banner_file_id) REFERENCES files(id) ON DELETE SET NULL,
    FOREIGN KEY (created_by)     REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE KEY uq_tenant_code (tenant_id, scheme_code),
    INDEX idx_tenant_active_dates (tenant_id, is_active, valid_from, valid_to)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 48: crm_scheme_dealer_targets
-- Per-dealer volume/revenue targets within a parent-company scheme.
-- SchemeService tracks attainment in real-time by joining sales data.
-- ============================================================
CREATE TABLE crm_scheme_dealer_targets (
    id              BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id       BIGINT UNSIGNED  NOT NULL,
    scheme_id       BIGINT UNSIGNED  NOT NULL,
    dealer_id       INT UNSIGNED     NOT NULL,
    volume_target   SMALLINT UNSIGNED NOT NULL DEFAULT 0  COMMENT 'Units to sell within scheme period',
    revenue_target  DECIMAL(12,2)    NULL                 COMMENT 'INR revenue target (optional)',
    incentive_on_hit DECIMAL(10,2)   NULL                 COMMENT 'Bonus INR paid to dealer on target hit',
    volume_achieved SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    revenue_achieved DECIMAL(12,2)   NOT NULL DEFAULT 0.00,
    target_hit      TINYINT(1)       NOT NULL DEFAULT 0,
    target_hit_at   TIMESTAMP        NULL,
    created_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (scheme_id) REFERENCES crm_schemes(id) ON DELETE CASCADE,
    FOREIGN KEY (dealer_id) REFERENCES users(id),
    UNIQUE KEY uq_scheme_dealer (scheme_id, dealer_id),
    INDEX idx_tenant_scheme (tenant_id, scheme_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 49: crm_dealer_sales_daily
-- Pre-aggregated daily sales metrics per dealer. Populated nightly by
-- DealerSalesRollupJob from driver_handshakes + delivery_incentives +
-- claims. Powers dealer sales graphs with O(1) range queries.
-- ============================================================
CREATE TABLE crm_dealer_sales_daily (
    id              BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id       BIGINT UNSIGNED  NOT NULL,
    dealer_id       INT UNSIGNED     NOT NULL,
    sale_date       DATE             NOT NULL,
    batteries_delivered SMALLINT UNSIGNED NOT NULL DEFAULT 0  COMMENT 'Handshakes completed',
    claims_raised   SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    replacements_done SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    incentives_paid DECIMAL(10,2)    NOT NULL DEFAULT 0.00,
    active_customers INT UNSIGNED    NOT NULL DEFAULT 0       COMMENT 'Distinct customers served',
    created_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (dealer_id) REFERENCES users(id),
    UNIQUE KEY uq_dealer_date (tenant_id, dealer_id, sale_date),
    INDEX idx_tenant_dealer_date (tenant_id, dealer_id, sale_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 50: crm_unsubscribe_tokens
-- Single-use signed tokens embedded in campaign email footers.
-- Allows customers to self-service opt-out without logging in.
-- Token = SHA-256(recipient_id + campaign_id + secret_salt) stored
-- hashed; plaintext sent in URL only.
-- ============================================================
CREATE TABLE crm_unsubscribe_tokens (
    id              BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id       BIGINT UNSIGNED  NOT NULL,
    recipient_id    BIGINT UNSIGNED  NOT NULL              COMMENT 'FK crm_campaign_recipients.id',
    token_hash      CHAR(64)         NOT NULL              COMMENT 'SHA-256 of plaintext token',
    channel         ENUM('EMAIL','WHATSAPP','ALL') NOT NULL,
    used            TINYINT(1)       NOT NULL DEFAULT 0,
    expires_at      TIMESTAMP        NOT NULL,
    created_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)    REFERENCES tenants(id),
    FOREIGN KEY (recipient_id) REFERENCES crm_campaign_recipients(id) ON DELETE CASCADE,
    INDEX idx_token_hash (token_hash),
    INDEX idx_recipient  (recipient_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 51: claim_tracking_tokens
-- One cryptographically random token per claim.
-- Embedded as a URL in every claim confirmation & status-change email/WhatsApp.
-- No authentication required to use — the token IS the credential.
-- Token = hex(random_bytes(32)), stored as-is (NOT hashed) because it is
-- a long-lived secret URL; HTTPS is the transport-layer protection.
-- Reissued if expired (claim re-opened edge case); old token deleted first.
-- ============================================================
CREATE TABLE claim_tracking_tokens (
    id              BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id       BIGINT UNSIGNED  NOT NULL,
    claim_id        INT UNSIGNED     NOT NULL,
    token           CHAR(64)         NOT NULL  COMMENT 'hex(random_bytes(32)) — secret URL token',
    expires_at      TIMESTAMP        NOT NULL  COMMENT 'claim.created_at + TRACKING_TOKEN_TTL_DAYS',
    view_count      INT UNSIGNED     NOT NULL DEFAULT 0,
    last_viewed_at  TIMESTAMP        NULL,
    created_at      TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_claim  (claim_id),
    UNIQUE KEY uq_token  (token),
    INDEX idx_tenant     (tenant_id),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (claim_id)  REFERENCES claims(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 52: ticket_lookup_attempts
-- Rate-limit log for the public /track/lookup endpoint.
-- Prevents enumeration of claim (ticket) numbers by unauthenticated actors.
-- ip_address stored as VARCHAR(45) to support both IPv4 and IPv6.
-- Rows pruned nightly by cron: DELETE WHERE attempted_at < NOW() - INTERVAL 1 DAY
-- ============================================================
CREATE TABLE ticket_lookup_attempts (
    id              BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    ip_address      VARCHAR(45)      NOT NULL,
    ticket_number   VARCHAR(50)      NULL      COMMENT 'The ticket number entered (for abuse analysis)',
    attempted_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_ip_time (ip_address, attempted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

---

## 5. Core Business Logic

### 5.1 Serial Number Validation

```
Regex:  /^[A-Z0-9]{14,15}$/
Input:  Uppercase-normalised before validation
```

**MFG Week/Year Decode** (positions configurable via `settings.serial_mfg_year_pos` and `serial_mfg_week_pos`):

```
Serial example:  A B 2 4 3 X X X X X X X X X
Index:           0 1 2 3 4 5 ...
                     ^   ^
                  year  week (2-digit)

year_char  = serial[2]          → map '0'=2020, '1'=2021, … '6'=2026
week_chars = serial[3..4]       → "43" = week 43
```

Provide a `BatteryService::decodeMfg(string $serial): array{year, week}` method that reads positions from the `settings` table for flexibility.

---

### 5.2 Orange Tick Logic

```
POST /claims/check-serial
  1. Normalize serial to uppercase, validate regex
  2. SELECT is_in_tally FROM batteries WHERE serial_number = :serial
  3a. Found AND is_in_tally = 1  →  Green; proceed with claim form
  3b. Found AND is_in_tally = 0  →  Orange tick; require orange_tick_photo upload
  3c. Not found                  →  Orange tick; INSERT battery(serial, is_in_tally=0);
                                     require orange_tick_photo upload
  4. Photo uploaded → compress client-side (see §7) → POST multipart
  5. Server: validate MIME = image/webp, max 2MB, store to storage/uploads/orange_tick/
```

---

### 5.3 Edit Lock Logic

```
Claim becomes read-only once status passes SUBMITTED.

Primary guard — STATUS-BASED (immune to is_locked flag being reset accidentally):
  if (!in_array($claim->status, ['DRAFT', 'SUBMITTED'], true)) {
      throw new BusinessRuleException('Claim is read-only after leaving SUBMITTED status');
  }
retain is_locked = 1 as a secondary UX hint only.

Driver task completion trigger:
  driver_tasks.status = 'DONE' AND task_type IN ('PICKUP_SERVICE','DELIVERY_*')
  → Set claims.is_locked = 1, claims.status = 'DRIVER_RECEIVED'

Enforcement in ClaimController::update():
  // Status-based lock — cannot be bypassed by resetting the flag
  if (!in_array($claim->status, ['DRAFT', 'SUBMITTED'], true)) {
      throw new BusinessRuleException('Claim is read-only after it leaves SUBMITTED status');
  }
```

---

### 5.4 Battery Lineage (Recursive CTE)

> **`mother_battery_id` = immediate parent only (linked-list).** It does NOT point to the original root.
> `Replacement 2.mother_battery_id → Replacement 1` (NOT → Original Mother).
> Use the recursive CTE below to traverse the full chain in both directions.

```sql
-- Cycle guard (§11.20): cap recursion depth to 50 hops per session.
-- MySQL default @@cte_max_recursion_depth = 1000 will spin indefinitely on a circular
-- mother_battery_id reference (A→B→C→A). 50 is safe: no real battery chain will exceed it.
SET @@cte_max_recursion_depth = 50;

-- Given ANY serial in a replacement chain, return full history
WITH RECURSIVE lineage AS (
    -- Anchor: find the ultimate mother (no mother_battery_id)
    SELECT b.id, b.serial_number, b.mother_battery_id,
           b.status, b.mfg_year, b.mfg_week, 0 AS generation
    FROM   batteries b
    WHERE  b.id = :start_id

    UNION ALL

    -- Recurse UP to find root (halts at depth 50 if cycle exists)
    SELECT p.id, p.serial_number, p.mother_battery_id,
           p.status, p.mfg_year, p.mfg_week, l.generation - 1
    FROM   batteries p
    JOIN   lineage   l ON p.id = l.mother_battery_id
    WHERE  ABS(l.generation) < 50   -- secondary cycle guard per-row
),
root AS (SELECT id FROM lineage ORDER BY generation LIMIT 1),
full_chain AS (
    -- Now recurse DOWN from root
    SELECT b.id, b.serial_number, b.mother_battery_id,
           b.status, b.mfg_year, b.mfg_week, 0 AS depth
    FROM   batteries b
    JOIN   root      r ON b.id = r.id

    UNION ALL

    SELECT b.id, b.serial_number, b.mother_battery_id,
           b.status, b.mfg_year, b.mfg_week, fc.depth + 1
    FROM   batteries b
    JOIN   full_chain fc ON b.mother_battery_id = fc.id
    WHERE  fc.depth < 50   -- secondary cycle guard per-row
)
SELECT * FROM full_chain ORDER BY depth;
-- depth 0 = Mother, depth 1 = Replacement 1, depth 2 = Replacement 2, …
```

Expose via `BatteryService::getLineage(int $batteryId): array` called from `ClaimController::lineage()`.

---

### 5.5 Nightly Audit Equation

```
Corrected Van Stock at End of Day
  = Morning Load  (action='MORNING_LOAD')
  + Pickups       (action='PICKED_UP')
  - Deliveries    (action='DELIVERED')
  - Inwarded      (action='INWARD')      ← batteries handed to service centre; MUST be subtracted

SQL:
SELECT
    SUM(CASE WHEN action='MORNING_LOAD' THEN  1 ELSE 0 END) +
    SUM(CASE WHEN action='PICKED_UP'    THEN  1 ELSE 0 END) -
    SUM(CASE WHEN action='DELIVERED'    THEN  1 ELSE 0 END) -
    SUM(CASE WHEN action='INWARD'       THEN  1 ELSE 0 END) AS expected_eod
FROM driver_stock
WHERE driver_id = :id AND stock_date = CURDATE();

Driver physically scans each unit at day-end.
If scanned count ≠ expected_eod → block logout, show discrepancy list.
Discrepancy → audit_log entry with severity='HIGH'.
Persist result to driver_eod_audits (TABLE 21) for historical reporting.
```

---

### 5.6 Driver Route Map Pin Logic

```javascript
// maps.js
const PIN_COLORS = {
  PENDING: '#FF4444',   // Red
  ACTIVE:  '#FF8800',   // Orange (in-progress)
  DONE:    '#22BB44',   // Green
  SKIPPED: '#888888',   // Grey
};

tasks.forEach(task => {
  const marker = new google.maps.Marker({
    position: { lat: task.dealer_lat, lng: task.dealer_lng },
    map,
    icon: { path: google.maps.SymbolPath.CIRCLE,
            fillColor: PIN_COLORS[task.status],
            fillOpacity: 1, strokeWeight: 0, scale: 10 },
    title: `${task.task_type} – ${task.claim_number}`
  });
  marker.addListener('click', () => openTaskPanel(task.id));
});
```

---

### 5.7 Claim Status State Machine

All status transitions **must** go through `ClaimService::transition()`. Direct `UPDATE claims SET status=?` outside this method is forbidden.

```php
// ClaimService — legal transitions only
const ALLOWED = [
    'DRAFT'            => ['SUBMITTED'],
    'SUBMITTED'        => ['DRIVER_RECEIVED'],
    'DRIVER_RECEIVED'  => ['IN_TRANSIT'],
    'IN_TRANSIT'       => ['AT_SERVICE'],
    'AT_SERVICE'       => ['DIAGNOSED'],
    'DIAGNOSED'        => ['REPLACED', 'READY_FOR_RETURN'],
    //   REPLACED         only when service_jobs.diagnosis = 'REPLACE'
    //   READY_FOR_RETURN only when service_jobs.diagnosis = 'OK'
    'READY_FOR_RETURN' => ['CLOSED'],
    'REPLACED'         => ['CLOSED'],
];

public function transition(int $claimId, string $toStatus, int $byUserId): void {
    $this->db->beginTransaction();
    try {
        $row = $this->db->query(
            "SELECT status FROM claims WHERE id = ? FOR UPDATE", [$claimId]
        )->fetch();

        if (!isset(self::ALLOWED[$row['status']])
            || !in_array($toStatus, self::ALLOWED[$row['status']], true)) {
            throw new BusinessRuleException(
                "Illegal transition: {$row['status']} → {$toStatus}"
            );
        }

        $this->db->exec(
            "UPDATE claims SET status = ?, updated_at = NOW() WHERE id = ?",
            [$toStatus, $claimId]
        );
        $this->db->exec(
            "INSERT INTO claim_status_history (claim_id, from_status, to_status, changed_by)
             VALUES (?, ?, ?, ?)",
            [$claimId, $row['status'], $toStatus, $byUserId]
        );
        $this->db->commit();
    } catch (\Throwable $e) {
        $this->db->rollBack();
        throw $e;
    }
}
```

**"OK" diagnosis path** in `ServiceController::diagnose()`:
```php
if ($diagnosis === 'OK') {
    $this->claimService->transition($claimId, 'READY_FOR_RETURN', $userId);
    $this->db->exec(
        "UPDATE claims SET closed_without_replacement = 1 WHERE id = ?", [$claimId]
    );
}
```

---

### 5.8 Claim Number Generation (Race-Free, Tenant-Scoped)

> **Breaking change from v2.0:** The global `claim_sequences` table is REPLACED by
> `tenant_sequences (tenant_id, seq_name)` (TABLE 30). Each tenant gets its own
> independent counter, preventing cross-tenant number inference.
> Format: `{TENANT_SLUG}-CLM-{YEAR}-{NNNNN}` e.g. `ACME-CLM-2026-00001`.

```php
// ClaimService::generateClaimNumber(int $tenantId): string
// Uses SELECT … FOR UPDATE on tenant_sequences to prevent duplicate numbers
// under concurrent load. Sequence resets each calendar year (reset_cycle=yearly).

public function generateClaimNumber(int $tenantId): string {
    $tenant = $this->tenantRepo->find($tenantId);  // cached
    $seqName = 'CLM-' . date('Y');
    $this->db->beginTransaction();
    try {
        // Pessimistic lock on this tenant+sequence row
        $row = $this->db->query(
            "SELECT current_val FROM tenant_sequences
             WHERE tenant_id = ? AND seq_name = ? FOR UPDATE",
            [$tenantId, $seqName]
        )->fetch();

        if (!$row) {
            // First claim of the year for this tenant
            $this->db->exec(
                "INSERT INTO tenant_sequences (tenant_id, seq_name, current_val, reset_cycle)
                 VALUES (?, ?, 1, 'yearly')",
                [$tenantId, $seqName]
            );
            $next = 1;
        } else {
            $next = (int) $row['current_val'] + 1;
            $this->db->exec(
                "UPDATE tenant_sequences SET current_val = ?
                 WHERE tenant_id = ? AND seq_name = ?",
                [$next, $tenantId, $seqName]
            );
        }

        $this->db->commit();

        // e.g. ACME-CLM-2026-00001
        return strtoupper($tenant->slug)
             . '-CLM-' . date('Y')
             . '-' . str_pad($next, 5, '0', STR_PAD_LEFT);
    } catch (\Throwable $e) {
        $this->db->rollBack();
        throw $e;
    }
}
```

---

### 5.9 OTP / Auth Rate Limiting (Multi-Dimensional)

> Three independent rate-limit axes protect against distributed brute-force.
> All checks use the updated `login_attempts` schema (TABLE 19).

```php
// AuthService::checkRateLimit(
//     string $identifier,   // email or phone — pre-auth key
//     string $ip,
//     ?int   $tenantId,     // NULL on public send-OTP route
//     string $attemptType   // SEND_OTP | VERIFY_OTP | REFRESH_TOKEN
// ): void
// Called BEFORE any token lookup or credential check.

public function checkRateLimit(
    string $identifier,
    string $ip,
    ?int $tenantId,
    string $attemptType = 'VERIFY_OTP'
): void {
    $window = date('Y-m-d H:i:s', strtotime('-10 minutes'));

    // Axis 1: per identifier (stops single-account hammering from many IPs)
    $byIdentifier = (int) $this->db->query(
        "SELECT COUNT(*) FROM login_attempts
         WHERE identifier = ? AND attempt_type = ? AND success = 0
         AND attempted_at > ?",
        [$identifier, $attemptType, $window]
    )->fetchColumn();

    // Axis 2: per IP (stops credential-stuffing / distributed spray)
    $byIp = (int) $this->db->query(
        "SELECT COUNT(*) FROM login_attempts
         WHERE ip_address = ? AND attempt_type = ? AND success = 0
         AND attempted_at > ?",
        [$ip, $attemptType, $window]
    )->fetchColumn();

    // Axis 3: per tenant burst (stops bulk-compromise of one tenant)
    $byTenant = 0;
    if ($tenantId !== null) {
        $byTenant = (int) $this->db->query(
            "SELECT COUNT(*) FROM login_attempts
             WHERE tenant_id = ? AND attempt_type = ? AND success = 0
             AND attempted_at > ?",
            [$tenantId, $attemptType, $window]
        )->fetchColumn();
    }

    // Thresholds (tunable per attempt_type)
    $limits = ['SEND_OTP' => [3, 20, 50], 'VERIFY_OTP' => [5, 30, 100], 'REFRESH_TOKEN' => [10, 50, 200]];
    [$limId, $limIp, $limTenant] = $limits[$attemptType] ?? [5, 30, 100];

    if ($byIdentifier >= $limId || $byIp >= $limIp || $byTenant >= $limTenant) {
        // Log CRITICAL audit event regardless of which axis triggered
        $this->db->exec(
            "INSERT INTO audit_logs
             (tenant_id, user_id, action, entity_type, ip_address, severity, new_values)
             VALUES (?, NULL, 'auth.rate_limited', 'login_attempts', ?, 'CRITICAL', ?)",
            [
                $tenantId,
                $ip,
                json_encode([
                    'identifier' => $identifier,
                    'type'       => $attemptType,
                    'by_id'      => $byIdentifier,
                    'by_ip'      => $byIp,
                    'by_tenant'  => $byTenant,
                ])
            ]
        );
        throw new AuthException('Too many failed attempts. Retry in 10 minutes.');
    }
}
```
---

### 5.10 Delivery Incentive Gating (Handshake-Required)

```php
// IncentiveService::recordIfEligible(int $taskId, int $handshakeId): void
// Called ONLY from DriverController::handshake(), after a successful handshake INSERT.
// This is the sole place delivery_incentives records are created.

public function recordIfEligible(int $taskId, int $handshakeId): void {
    $task = $this->db->query(
        "SELECT t.task_type, t.claim_id, r.driver_id
         FROM driver_tasks t
         JOIN driver_routes r ON r.id = t.route_id
         WHERE t.id = ? AND t.status = 'DONE'",
        [$taskId]
    )->fetch();

    if (!$task) return;
    if (!in_array($task['task_type'],
        ['DELIVERY_NEW', 'DELIVERY_REPLACEMENT'], true)) return;

    $amount = (float) $this->db->query(
        "SELECT `value` FROM settings WHERE `key` = 'delivery_incentive'"
    )->fetchColumn();

    $this->db->exec(
        "INSERT IGNORE INTO delivery_incentives
         (driver_id, task_id, claim_id, handshake_id, amount, task_type, delivery_date)
         VALUES (?, ?, ?, ?, ?, ?, CURDATE())",
        [$task['driver_id'], $taskId, $task['claim_id'],
         $handshakeId, $amount, $task['task_type']]
    );
}
```

> `INSERT IGNORE` ensures idempotency if the endpoint is called twice. Both `DELIVERY_NEW` and `DELIVERY_REPLACEMENT` earn the incentive; `task_type` column records which type for reporting.

---

### 5.11 Tally Import UPSERT Strategy

On re-import of the same or refreshed Excel file (duplicate serials must not corrupt claimed batteries):

```php
// TallyService::importExcel() — per-row UPSERT
// XXE + Zip Bomb guard (§11.18): disable XML entity expansion before phpspreadsheet opens
// the file. Modern .xlsx files are ZIP archives containing XML; a malicious file can define
// an XXE entity that reads /etc/passwd or issues SSRF requests. libxml_disable_entity_loader
// prevents this. setReadDataOnly(true) enables streaming mode, capping peak memory usage.
libxml_disable_entity_loader(true);
$reader = \PhpOffice\PhpSpreadsheet\IOFactory::createReaderForFile($filePath);
$reader->setReadDataOnly(true);   // streaming: skip style/chart objects — drastically limits RAM
$spreadsheet = $reader->load($filePath);

$this->db->exec("
    INSERT INTO batteries (serial_number, is_in_tally, mfg_year, mfg_week, model)
    VALUES (:serial, 1, :year, :week, :model)
    ON DUPLICATE KEY UPDATE
        is_in_tally = 1,
        mfg_year    = VALUES(mfg_year),
        mfg_week    = VALUES(mfg_week),
        model       = IF(VALUES(model) IS NOT NULL, VALUES(model), model),
        -- status is intentionally NOT updated: CLAIMED / AT_SERVICE state is preserved
        updated_at  = NOW()
", [':serial' => $serial, ':year' => $year, ':week' => $week, ':model' => $model]);
```

Rules:
- Serial **not in table** → fresh `INSERT` → `inserted_rows++`
- Serial exists, **status not CLAIMED** → UPSERT refreshes MFG data → `upserted_rows++`
- Serial exists, **status = CLAIMED / AT_SERVICE** → same UPSERT runs; `status` column untouched → `skipped_rows++` (track separately by checking rows_affected == 1 vs 2)

---

### 5.12 Async Email Queue (OTP Dispatch)

OTP emails are **never sent synchronously** during the HTTP request.

```php
// NotificationService::queueOtp(string $email, string $plainOtp): void
public function queueOtp(string $email, string $plainOtp): void {
    $body = "Your OTP code is: <strong>{$plainOtp}</strong><br>Valid for 10 minutes. Do not share.";
    $this->db->exec(
        "INSERT INTO email_queue (recipient, subject, body)
         VALUES (?, 'Your Login OTP', ?)",
        [$email, $body]
    );
    // plainOtp is used only here; it is NEVER stored to otp_tokens
    // otp_tokens stores: hash('sha256', $plainOtp) — see AuthService::sendOtp()
}

// bin/process-email-queue.php — run every minute via cron
// * * * * * php /var/www/bin/process-email-queue.php >> /var/log/email-queue.log 2>&1
// Fetches up to 20 PENDING rows, sends via PHPMailer,
// marks SENT or increments attempts (FAILED after 3).
```

---

### 5.13 Service Contracts (Interface-First Design)

All domain services implement an interface. This allows:
- **Unit testing** with mock implementations
- **Future micro-service extraction** (swap concrete class without touching controllers)
- **Compile-time contract enforcement** (PHP strict types + static analysis)

```php
// app/Modules/Claims/Services/ClaimServiceInterface.php
interface ClaimServiceInterface {
    public function create(ClaimDTO $dto): Claim;
    public function submit(int $claimId, int $actorId): void;
    public function transition(int $claimId, string $toStatus, int $actorId, ?string $note = null): void;
    public function lock(int $claimId, int $byUserId): void;
    public function unlock(int $claimId, int $byUserId): void;
    public function findById(int $id): ?Claim;
    public function listForTenant(int $tenantId, array $filters, int $page, int $perPage): PaginatedResult;
}

// app/Modules/Batteries/Services/BatteryServiceInterface.php
interface BatteryServiceInterface {
    public function validateSerial(string $serial): bool;
    public function decodeMfg(string $serial): array;          // ['year'=>int, 'week'=>int]
    public function getLineage(int $batteryId): array;          // CTE result
    public function markOrangeTick(int $batteryId, int $fileId): void;
}

// app/Shared/Storage/StorageDriver.php
interface StorageDriver {
    public function put(string $key, string $localPath, string $mimeType): string;  // returns disk_path
    public function getSignedUrl(string $diskPath, int $ttlSeconds = 3600): string;
    public function delete(string $diskPath): void;
}

// app/Shared/Queue/QueueDriverInterface.php
interface QueueDriverInterface {
    public function push(string $jobClass, array $payload, int $delay = 0): string; // returns job_id
    public function pop(string $queue): ?array;
    public function ack(string $jobId): void;
    public function fail(string $jobId, string $reason): void;
}
```

> **Binding:** Register concrete classes in `bootstrap/bindings.php`:
> `$container->bind(ClaimServiceInterface::class, ClaimService::class);`
> `$container->bind(StorageDriver::class, fn() => match(env('STORAGE_DRIVER')) { 's3' => new S3StorageDriver(), default => new LocalStorageDriver() });`

---

### 5.14 Tenant Middleware & Context Scoping

> **Security rule:** JWT claim is the SOLE authoritative source of tenant identity
> on authenticated routes. Subdomain / `X-Tenant-ID` serve only as routing hints on
> public (pre-auth) endpoints and MUST match the JWT tenant before being trusted.

```
Resolution priority on every request
─────────────────────────────────────
1. If Authorization: Bearer <token> is present:
   a. Decode JWT; verify iss = APP_URL, aud = "battery-saas", kid matches current key.
   b. Extract tenant_id + tenant_slug from JWT claims.
   c. Assert subdomain (if present) == JWT tenant slug → 403 if mismatch.
   d. X-Tenant-ID header is IGNORED on authenticated routes.

2. If no Bearer token (public / pre-auth routes only):
   a. Derive tenant from subdomain (acme.example.com → slug = "acme").
   b. Accept X-Tenant-ID header as fallback (e.g. native app / API client
      that cannot set a subdomain).
   c. Load tenant row; assert is_active = 1.
   d. Store in RequestContext for OTP send, rate-limit, and token issuance.

3. Plan enforcement (PlanGuard) runs AFTER tenant resolution:
   PlanGuard::check($tenant, 'claims.create') → 429 / 403 if quota exceeded.
```

```php
// TenantMiddleware::handle(Request $request, Closure $next): Response
public function handle(Request $request, Closure $next): Response
{
    $token = $this->parseBearerToken($request);

    if ($token !== null) {
        // ── Authenticated route ──────────────────────────────────
        try {
            $claims = $this->jwt->decode($token, [
                'iss' => config('app.url'),
                'aud' => 'battery-saas',
            ]);
        } catch (JwtException $e) {
            return response()->json(['error' => 'invalid_token'], 401);
        }

        $tenant = $this->tenantRepo->findOrFail((int) $claims->tenant_id);

        // Subdomain MUST match JWT when present (prevents host-header injection)
        $subdomain = $this->extractSubdomain($request->getHost());
        if ($subdomain && $subdomain !== $tenant->slug) {
            return response()->json(['error' => 'tenant_mismatch'], 403);
        }

        if (!$tenant->is_active) {
            return response()->json(['error' => 'tenant_suspended'], 403);
        }

        RequestContext::set($tenant, (int) $claims->sub);

    } else {
        // ── Pre-auth public route (send-OTP, login) ──────────────
        $slug = $this->extractSubdomain($request->getHost())
             ?? $request->header('X-Tenant-ID');       // only accepted pre-auth

        if (!$slug) {
            return response()->json(['error' => 'tenant_required'], 400);
        }

        $tenant = $this->tenantRepo->findBySlug($slug);
        if (!$tenant || !$tenant->is_active) {
            return response()->json(['error' => 'tenant_not_found'], 404);
        }

        RequestContext::setTenantOnly($tenant);
    }

    return $next($request);
}
```

**JWT key rotation (`kid`):** Each JWT header carries `kid` (key ID). `JwtKeyStore`
fetches the public key by `kid` from Redis (cache-aside, TTL 5 min). Old tokens with
superseded `kid` are rejected once the grace period (15 min overlap) expires.

**Tenant suspension re-check on refresh:** `POST /auth/refresh` always re-reads
`tenants.is_active` from DB (bypassing cache) so suspended tenants are blocked
within one refresh cycle even if the access token has not expired yet.
### 5.15 RBAC Migration Flag

When a tenant is first created all users inherit permissions from `legacy_role` (the ENUM on `users`).
Once the admin has seeded `user_roles` + `role_permissions` tables, they set:

```
tenant_settings.key = 'rbac_migrated', value = 'true'
```

`ApiAuthMiddleware` then switches permission resolution mode:

```php
if ($this->tenantSettings->get('rbac_migrated') === 'true') {
    // Authoritative path: user_roles → roles → role_permissions
    $permissions = $this->rbac->permissionsForUser($user->id);
} else {
    // Bootstrap path: derive permissions from legacy_role ENUM
    $permissions = LegacyRoleMapper::toPermissions($user->legacy_role);
}
```

**Rules:**
- Once set to `'true'`, this flag is **irreversible** (no rollback via API; requires DB intervention).
- The `/api/v1/admin/tenants/{id}/migrate-rbac` endpoint sets the flag only after validating that
  every active user has at least one `user_roles` row.
- `legacy_role` column is retained for audit history but is completely ignored post-migration.

### 5.17 File Serve — Quarantine & Integrity Guard

`FileController::serve()` MUST refuse delivery and return `403 file_unavailable` whenever any of these
conditions is true before streaming to the client:

```php
// FileController::serve(int $id, Request $request): Response
$file = File::findOrFail($id);

// 1. Ownership / tenant scope guard
abort_unless($file->tenant_id === $request->tenantId(), 403);

// 2. Quarantine / scan gate
if (
    $file->virus_scan_status === 'INFECTED'
    || $file->quarantined_at !== null
    || ($file->virus_scan_status === 'PENDING' && $file->isHighRiskType())
) {
    return response()->json(['error' => 'file_unavailable', 'reason' => 'quarantined'], 403);
}

// 3. Integrity check (SHA-256 of physical bytes must match stored checksum)
$physicalPath = storage_path('app/' . $file->storage_path);
if (hash_file('sha256', $physicalPath) !== $file->checksum_sha256) {
    // Integrity failure: quarantine immediately and alert
    $file->update(['quarantined_at' => now(), 'virus_scan_status' => 'INFECTED']);
    event(new FileIntegrityFailure($file));
    return response()->json(['error' => 'file_unavailable', 'reason' => 'integrity_failure'], 403);
}

// 4. Stream file only after all checks pass
```

`isHighRiskType()` returns `true` for extensions: `exe`, `sh`, `bat`, `cmd`, `ps1`, `php`, `py`, `js`.  
High-risk PENDING files are blocked until the async virus-scan worker completes.

---

### 5.18 CRM Lead Pipeline State Machine

A lead moves through a defined set of stages. Stage changes are recorded in `crm_lead_activities` (TABLE 41) for full auditability.

```
         ┌──────────────────────────────────────────────┐
         │                  LEAD STAGES                 │
         │                                              │
         │  NEW ──→ CONTACTED ──→ QUALIFIED ──→ PROPOSAL │
         │                                   ├──→ WON   │
         │                                   └──→ LOST   │
         │                                              │
         │  Any stage can transition directly to LOST.  │
         └──────────────────────────────────────────────┘
```

```php
// LeadService::transition(Lead $lead, string $newStage, int $actorId): void
//
// RULES
// 1. WON / LOST are terminal states — no further transitions.
// 2. Only allowed forward transitions (see matrix below).
// 3. Stage change fires LeadStageChanged event → listener updates
//    crm_customers.lifecycle_stage if WON (→ ACTIVE) or LOST.
// 4. Activity log row written atomically in the same DB transaction.

const ALLOWED_TRANSITIONS = [
    'NEW'       => ['CONTACTED', 'LOST'],
    'CONTACTED' => ['QUALIFIED', 'LOST'],
    'QUALIFIED' => ['PROPOSAL',  'LOST'],
    'PROPOSAL'  => ['WON',       'LOST'],
    'WON'       => [],  // terminal
    'LOST'      => [],  // terminal
];

DB::transaction(function() use ($lead, $newStage, $actorId) {
    if (! in_array($newStage, self::ALLOWED_TRANSITIONS[$lead->stage], true)) {
        throw new BusinessRuleException("INVALID_LEAD_TRANSITION");
    }
    $oldStage = $lead->stage;
    $lead->update([
        'stage'      => $newStage,
        'closed_at'  => in_array($newStage, ['WON','LOST']) ? now() : null,
    ]);
    CrmLeadActivity::create([
        'tenant_id'     => $lead->tenant_id,
        'lead_id'       => $lead->id,
        'user_id'       => $actorId,
        'activity_type' => 'STAGE_CHANGE',
        'old_stage'     => $oldStage,
        'new_stage'     => $newStage,
    ]);
    EventBus::dispatch(new LeadStageChanged($lead, $oldStage, $newStage));
});
```

**Lifecycle stage sync:** when a lead transitions to **WON**, `CustomerService::syncLifecycle()` upgrades `crm_customers.lifecycle_stage`:
- First WON → `ACTIVE`  
- Any subsequent WON on same customer → `REPEAT`  
- All leads LOST, no WON → `CHURNED` (cron run weekly)

---

### 5.19 Campaign Dispatch (Email + WhatsApp)

`CampaignService::dispatch(Campaign $campaign)` is called by `DispatchCampaignBatchJob`.

**Pre-dispatch checklist (all must pass or campaign is CANCELLED):**
1. `campaign.status = 'SCHEDULED'` → set `'DISPATCHING'`  
2. Resolve segment OR load explicit recipient list → build `crm_campaign_recipients` rows atomically  
3. **Opt-out filter:** `LEFT JOIN crm_opt_outs` on `(customer_id, channel IN (?, 'ALL'))` → exclude  
4. **Consent gate:** WhatsApp channel requires `customers.phone` to be in E.164 format and not NULL  
5. Render template per recipient using `TemplateRenderer::render($template, $vars)` — twig-sandbox, allow-listed variables only, no PHP execution

```php
// Campaign dispatch — chunked fan-out (max 500 per job to avoid memory exhaustion)
// Each chunk is pushed as a separate DispatchCampaignBatchJob onto the CRM queue.

public function dispatch(Campaign $campaign): void
{
    $this->assertStatus($campaign, 'SCHEDULED');
    $campaign->update(['status' => 'DISPATCHING', 'dispatched_at' => now()]);

    $recipientIds = $this->buildRecipientList($campaign); // writes to crm_campaign_recipients
    $campaign->update(['total_recipients' => count($recipientIds)]);

    foreach (array_chunk($recipientIds, 500) as $chunk) {
        Queue::push(new DispatchCampaignBatchJob($campaign->id, $chunk), queue: 'crm');
    }
}

// DispatchCampaignBatchJob::handle()
foreach ($recipientIds as $recipientId) {
    $recipient = CrmCampaignRecipient::find($recipientId);
    $customer  = $recipient->customer;

    // Skip if opted out (double-checked here in case of race)
    if (OptOutRepository::isOptedOut($customer->id, $recipient->channel)) {
        $recipient->update(['status' => 'OPTED_OUT']);
        continue;
    }

    $vars = [
        'customer_name' => $customer->name,
        'dealer_name'   => $recipient->campaign->tenant->name,
        'offer_details' => $recipient->campaign->scheme?->description ?? '',
        'scheme_name'   => $recipient->campaign->scheme?->name ?? '',
        'valid_until'   => $recipient->campaign->scheme?->valid_to ?? '',
        'cta_link'      => $this->buildCtaLink($recipient),
        'unsub_link'    => $this->buildUnsubLink($recipient),  // single-use token
    ];

    $rendered = TemplateRenderer::render($recipient->campaign->template, $vars);

    match ($recipient->channel) {
        'EMAIL'    => $this->emailChannel->send($recipient->address, $rendered),
        'WHATSAPP' => $this->whatsappChannel->send($recipient->address, $rendered),
    };

    $recipient->update(['status' => 'SENT', 'sent_at' => now()]);
    $campaign->increment('sent_count');
}
```

**Unsubscribe flow:**
1. Footer of every email contains `?unsub=<plaintext_token>`  
2. `GET /api/v1/crm/unsubscribe?token=<tok>` → `CampaignController::unsubscribe()`  
3. Lookup `crm_unsubscribe_tokens WHERE token_hash = SHA-256(tok) AND used=0 AND expires_at > NOW()`  
4. Mark token `used=1`, insert into `crm_opt_outs`, return 200 with confirmation page  
5. WhatsApp uses carrier/BSP-level opt-out webhook → mapped to same `crm_opt_outs` row

**Rate limits:**
- Email: ≤ 200 messages/min/tenant (SMTP throttle via `MAIL_RATE_PER_MIN` env var)  
- WhatsApp: ≤ 80 messages/min/tenant (BSP tier limit; configurable via `WA_RATE_PER_MIN`)

---

### 5.20 Segment Builder (JSON Rule Evaluator)

`SegmentService::resolve(Segment $segment): array` returns `[crm_customer_id, ...]`.

```php
// SECURITY: field names come from DB-stored JSON — NEVER interpolated raw into SQL.
// All fields are routed through a whitelist map to their safe column expression.

const FIELD_WHITELIST = [
    'lifecycle_stage'         => 'c.lifecycle_stage',
    'city'                    => 'c.city',
    'state'                   => 'c.state',
    'total_batteries_bought'  => 'c.total_batteries_bought',
    'last_purchase_days_ago'  => 'DATEDIFF(NOW(), c.last_purchase_at)',
    'dealer_id'               => 'c.dealer_id',
    'source'                  => 'c.source',
];

const OP_MAP = [
    'eq'  => '=',
    'neq' => '!=',
    'gt'  => '>',
    'gte' => '>=',
    'lt'  => '<',
    'lte' => '<=',
    'in'  => 'IN',
];

public function resolve(Segment $segment): array
{
    $rules   = json_decode($segment->rules, true);
    $clauses = $this->buildClauses($rules['conditions']);
    $joiner  = $rules['operator'] === 'OR' ? 'OR' : 'AND';

    $sql = "SELECT c.id FROM crm_customers c
            WHERE c.tenant_id = ? AND c.deleted_at IS NULL
              AND (" . implode(" {$joiner} ", $clauses['sql']) . ")";

    return DB::select($sql, array_merge([$segment->tenant_id], $clauses['bindings']));
}

private function buildClauses(array $conditions): array
{
    $sqls = []; $bindings = [];
    foreach ($conditions as $cond) {
        $col = self::FIELD_WHITELIST[$cond['field']]
            ?? throw new BusinessRuleException("INVALID_SEGMENT_FIELD: {$cond['field']}");
        $op  = self::OP_MAP[$cond['op']]
            ?? throw new BusinessRuleException("INVALID_SEGMENT_OP: {$cond['op']}");

        if ($op === 'IN') {
            $placeholders = implode(',', array_fill(0, count($cond['value']), '?'));
            $sqls[]       = "{$col} IN ({$placeholders})";
            $bindings      = array_merge($bindings, $cond['value']);
        } else {
            $sqls[]     = "{$col} {$op} ?";
            $bindings[] = $cond['value'];
        }
    }
    return ['sql' => $sqls, 'bindings' => $bindings];
}
```

---

### 5.21 Parent Company Scheme Distribution & Attainment

**Scheme lifecycle:**

```
ADMIN/CRM_MGR creates scheme (TABLE 47)
        ↓
Dealer targets set per scheme (TABLE 48)
        ↓
DealerSalesRollupJob runs nightly:
  UPDATE crm_scheme_dealer_targets
     SET volume_achieved  = (SELECT COUNT(*) FROM driver_handshakes
                             WHERE dealer_id = ? AND handshake_at BETWEEN s.valid_from AND s.valid_to),
         revenue_achieved = (derived from delivery_incentives in same window)
   WHERE target_hit = 0;
        ↓
SchemeService::checkAttainment(Scheme $scheme):
  for each target row WHERE target_hit=0:
    if volume_achieved >= volume_target:
      UPDATE target_hit=1, target_hit_at=NOW()
      EventBus::dispatch(new SchemeTargetHit($target))
          → Notification to dealer via email + WhatsApp
          → Audit log entry
```

**Dealer dashboard widget (§13.3):** shows each active scheme with:
- Progress bar `volume_achieved / volume_target`
- Remaining days until `valid_to`
- Incentive amount unlocked on target hit

**Rules enforced by SchemeService:**
- A scheme's `valid_from` ≤ `valid_to` (validated on create)
- A dealer may not belong to conflicting schemes of the same type in overlapping date ranges
- Attainment is recalculated nightly; real-time preview endpoint recalculates on-demand without committing

---

### 5.22 Claim Tracking Token — Issuance, Embedding & Resolution

#### Token Lifecycle

```
ClaimService::create()
        ↓
TrackingService::issue($claim)
  1. token = bin2hex(random_bytes(32))          // 64-char hex; 256-bit entropy
  2. expires_at = $claim->created_at + env('TRACKING_TOKEN_TTL_DAYS', 90) days
  3. INSERT INTO claim_tracking_tokens
         (tenant_id, claim_id, token, expires_at)
         VALUES (:tid, :cid, :tok, :exp)
        ON DUPLICATE KEY UPDATE
         token=:tok, expires_at=:exp,
         view_count=0, last_viewed_at=NULL
         -- Handles edge case: claim re-opened after CLOSED → fresh token
  4. return TRACKING_URL_BASE . '/track/' . $token
        // e.g.  https://track.mybatteryapp.com/track/3fa2c84d...
```

#### URL Resolution (Public — no auth required)

```
GET /track/{token}          (HTML page for customers)
GET /api/v1/track/{token}   (JSON — for bot / mobile)

TrackingController::resolve(string $token): array
  1. Validate: token is exactly 64 hex chars — else 404
  2. SELECT ctt.*, c.claim_number, c.status, c.created_at,
            c.diagnosis_notes, c.replacement_serial,
            u.name  AS dealer_name,
            sc.name AS service_centre_name
     FROM   claim_tracking_tokens ctt
     JOIN   claims  c ON c.id = ctt.claim_id
     JOIN   users   u ON u.id = c.dealer_id
     LEFT JOIN service_centres sc ON sc.id = c.service_centre_id
     WHERE  ctt.token = :token
  3. If not found → 404 (generic "Invalid or expired link" message; do NOT
     confirm whether the claim exists — prevents enumeration)
  4. If expires_at < NOW() → return expired view:
        "This tracking link has expired. Please contact your dealer."
  5. Apply PII masking rules (§14.6) before returning payload
  6. UPDATE claim_tracking_tokens
        SET view_count = view_count + 1, last_viewed_at = NOW()
      WHERE token = :token
  7. Return masked tracking payload (§14.1)
```

#### Ticket Number Lookup (Rate-Limited Public Endpoint)

```
POST /track/lookup   body: { "ticket_number": "ACME-CLM-2026-00001" }

TrackingController::lookup(string $ticketNumber): RedirectResponse
  Rate-limit check (TABLE 52):
    count = SELECT COUNT(*) FROM ticket_lookup_attempts
             WHERE ip_address = :ip AND attempted_at > NOW() - INTERVAL 15 MINUTE
    if count >= 10:
      return 429 "Too many lookup attempts. Please try again later."

  INSERT INTO ticket_lookup_attempts (ip_address, ticket_number)
    VALUES (:ip, :ticket)                   // always log the attempt

  SELECT ctt.token
    FROM claim_tracking_tokens ctt
    JOIN claims c ON c.id = ctt.claim_id
   WHERE c.claim_number = :ticketNumber
     AND c.tenant_id    = TenantContext::id()    // tenant scoped — no cross-tenant leak
     AND ctt.expires_at > NOW()
   LIMIT 1

  If not found → 422 "Ticket not found or link has expired."
                  // Generic — do NOT confirm whether claim number exists
  Else → 302 redirect to /track/{token}
```

#### Token Injection into Notifications

```php
// app/Modules/Notifications/Listeners/NotifyOnClaimChange.php

class NotifyOnClaimChange implements EventListenerInterface
{
    public function handle(ClaimStatusChanged|ClaimCreated $event): void
    {
        $claim       = $event->claim;
        $trackingUrl = TrackingService::getOrCreateToken($claim->id, $claim->tenantId);

        $body = $this->renderTemplate($claim, [
            '{{tracking_url}}' => $trackingUrl,
            '{{claim_number}}' => $claim->claimNumber,
            '{{status_label}}' => ClaimStatusLabels::forCustomer($claim->status),
        ]);

        // Email notification (TABLE 20 email_queue)
        EmailQueue::push(
            tenantId:  $claim->tenantId,
            recipient: $claim->customerEmail,
            subject:   "Repair Update: {$claim->claimNumber}",
            body:      $body,
        );

        // WhatsApp notification (Phase 3 — guarded by feature flag)
        if (config('features.whatsapp_tracking_alerts')) {
            WhatsAppChannel::send(
                to:      $claim->customerPhone,
                message: WhatsAppTemplates::repairUpdate($claim, $trackingUrl),
            );
        }
    }
}
```

**`TrackingService::getOrCreateToken()`** — idempotent helper:

```php
// Returns existing token URL if valid, otherwise re-issues.
public static function getOrCreateToken(int $claimId, int $tenantId): string
{
    $row = DB::queryOne(
        'SELECT token, expires_at FROM claim_tracking_tokens
          WHERE claim_id = ? AND expires_at > NOW()', [$claimId]
    );
    if ($row) {
        return env('TRACKING_URL_BASE') . '/track/' . $row['token'];
    }
    // Re-issue (token expired or not yet created)
    return TrackingService::issue(ClaimRepository::find($claimId));
}
```

#### Environment Variables

```dotenv
# Tracking
TRACKING_URL_BASE=https://track.yourdomain.com   # Base URL for public tracking links
                                                  # Can equal APP_URL if on same domain
TRACKING_TOKEN_TTL_DAYS=90                       # Days a tracking link stays valid
```

---

## 6. API Route Map

**Dual routing:** `/api/v1/*` (stateless JWT) and `/web/*` (stateful session).
All JSON endpoints return the **standard envelope** below.

```json
// SUCCESS
{
  "success": true,
  "data": { ... },
  "meta": {
    "request_id": "a3f2c1d0-...",
    "tenant_id":  12,
    "pagination": { "page": 1, "per_page": 25, "total": 342, "pages": 14 }
  },
  "error": null
}

// ERROR
{
  "success": false,
  "data": null,
  "meta": { "request_id": "a3f2c1d0-..." },
  "error": { "code": "CLAIM_LOCKED", "message": "Claim is locked by another user.", "details": {} }
}
```

> **Auth header (API routes):** `Authorization: Bearer <access_token>`  
> **CSRF header (web routes):** `X-CSRF-Token: <token>`  
> **Tenant header (multi-tenant API clients):** `X-Tenant-ID: <slug>` (if not using subdomain)

### API v1 Routes — `/api/v1/*` (JWT, stateless)

> **Middleware stack:** `TenantMiddleware` → `ApiAuthMiddleware` (JWT) → `RoleMiddleware` → Controller

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| POST | `/api/v1/auth/send-otp` | Public | Send 6-digit OTP to email |
| POST | `/api/v1/auth/verify-otp` | Public | Validate OTP → issue JWT access + refresh tokens |
| POST | `/api/v1/auth/refresh` | Public (refresh token) | Rotate access token |
| DELETE | `/api/v1/auth/logout` | Any | Revoke refresh token |
| GET | `/api/v1/claims` | `claims.list` | Paginated claim list (tenant-scoped) |
| POST | `/api/v1/claims` | `claims.create` | Create claim |
| GET | `/api/v1/claims/{id}` | `claims.view` | Single claim + status history |
| PATCH | `/api/v1/claims/{id}` | `claims.edit` | Edit pre-lock fields |
| POST | `/api/v1/claims/{id}/submit` | `claims.submit` | Dealer submits claim |
| POST | `/api/v1/claims/{id}/lock` | `claims.lock` | Lock for processing |
| POST | `/api/v1/claims/{id}/unlock` | `claims.lock` | Release lock |
| POST | `/api/v1/claims/{id}/transition` | `claims.transition` | Admin state override |
| GET | `/api/v1/claims/{id}/lineage` | `claims.view` | Battery replacement chain |
| POST | `/api/v1/claims/check-serial` | `claims.create` | Orange-tick serial check |
| POST | `/api/v1/claims/{id}/files` | `claims.create` | Upload photo (orange-tick/proof) |
| GET | `/api/v1/driver/route` | `driver.view` | Today's route + task list |
| POST | `/api/v1/driver/routes/{id}/start` | `driver.routes` | Activate route |
| POST | `/api/v1/driver/tasks/{id}/scan` | `driver.tasks` | Record scanned serial |
| POST | `/api/v1/driver/tasks/{id}/skip` | `driver.tasks` | Skip with photo + reason |
| POST | `/api/v1/driver/tasks/{id}/complete` | `driver.tasks` | Mark task done |
| POST | `/api/v1/driver/handshakes` | `driver.handshake` | Upload batch photo + signature |
| POST | `/api/v1/driver/audit/scan` | `driver.audit` | Nightly audit serial scan |
| POST | `/api/v1/service/inward` | `service.inward` | Inward battery from driver |
| POST | `/api/v1/service/jobs/{id}/diagnose` | `service.diagnose` | Set OK / REPLACE |
| POST | `/api/v1/service/jobs/{id}/replace` | `service.replace` | Assign replacement serial |
| POST | `/api/v1/tally/import` | `tally.import` | Upload Excel → parse serials (queued) |
| GET | `/api/v1/tally/exports` | `tally.export` | List export files |
| GET | `/api/v1/tally/exports/{id}/download` | `tally.export` | Download replacement CSV |
| GET | `/api/v1/reports/finance` | `reports.finance` | Driver incentive summary |
| GET | `/api/v1/reports/analytics` | `reports.analytics` | Lemon batteries + MFG failures |
| GET | `/api/v1/settings` | `settings.view` | Read tenant settings |
| PUT | `/api/v1/settings/{key}` | `settings.edit` | Update single setting |
| GET | `/api/v1/files/{id}` | Any auth | Auth-gated signed file URL |
| GET | `/api/v1/health/live` | Public | Liveness: 200 OK always |
| GET | `/api/v1/health/ready` | Public | DB + Redis connectivity check |

### CRM API Routes — `/api/v1/crm/*`

> **Middleware stack (same as core):** `TenantMiddleware` → `ApiAuthMiddleware` → `RoleMiddleware` → Controller  
> All routes require `crm.*` permissions. Dealers see only their own customer/lead records.

**Customers**

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| GET | `/api/v1/crm/customers` | `crm.customers.list` | Paginated customer list; dealer-scoped automatically |
| POST | `/api/v1/crm/customers` | `crm.customers.create` | Create customer manually |
| GET | `/api/v1/crm/customers/{id}` | `crm.customers.view` | Customer detail + leads + activity timeline |
| PATCH | `/api/v1/crm/customers/{id}` | `crm.customers.edit` | Update profile fields |
| DELETE | `/api/v1/crm/customers/{id}` | `crm.customers.delete` | Soft-delete |
| GET | `/api/v1/crm/customers/{id}/leads` | `crm.leads.list` | All leads for customer |

**Leads / Pipeline**

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| GET | `/api/v1/crm/leads` | `crm.leads.list` | Kanban/list view of all pipeline leads |
| POST | `/api/v1/crm/leads` | `crm.leads.create` | Open new lead |
| GET | `/api/v1/crm/leads/{id}` | `crm.leads.view` | Lead detail + activity log |
| PATCH | `/api/v1/crm/leads/{id}` | `crm.leads.edit` | Update lead fields (expected value, follow-up) |
| POST | `/api/v1/crm/leads/{id}/transition` | `crm.leads.transition` | Move to next stage (§5.18) |
| POST | `/api/v1/crm/leads/{id}/activities` | `crm.leads.activity` | Log call/note/visit on a lead |
| GET | `/api/v1/crm/pipeline/summary` | `crm.leads.list` | Stage counts + total expected value per stage |

**Campaigns**

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| GET | `/api/v1/crm/campaigns` | `crm.campaigns.list` | List all campaigns with status + stats |
| POST | `/api/v1/crm/campaigns` | `crm.campaigns.create` | Create campaign (DRAFT) |
| GET | `/api/v1/crm/campaigns/{id}` | `crm.campaigns.view` | Campaign detail + per-recipient status |
| PATCH | `/api/v1/crm/campaigns/{id}` | `crm.campaigns.edit` | Edit a DRAFT campaign |
| POST | `/api/v1/crm/campaigns/{id}/schedule` | `crm.campaigns.send` | Schedule or immediately dispatch (§5.19) |
| POST | `/api/v1/crm/campaigns/{id}/cancel` | `crm.campaigns.send` | Cancel a SCHEDULED campaign |
| GET | `/api/v1/crm/campaigns/{id}/analytics` | `crm.campaigns.view` | Delivery funnel: sent/delivered/opened/clicked |
| GET | `/api/v1/crm/unsubscribe` | Public (token) | Self-service opt-out via unsubscribe token |

**Segments & Templates**

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| GET | `/api/v1/crm/segments` | `crm.campaigns.create` | List saved segments |
| POST | `/api/v1/crm/segments` | `crm.campaigns.create` | Create segment with JSON rules |
| POST | `/api/v1/crm/segments/{id}/preview` | `crm.campaigns.create` | Dry-run resolve → returns count + sample (§5.20) |
| GET | `/api/v1/crm/templates` | `crm.campaigns.create` | List message templates |
| POST | `/api/v1/crm/templates` | `crm.campaigns.create` | Create email/WhatsApp template |
| PATCH | `/api/v1/crm/templates/{id}` | `crm.campaigns.create` | Update template |

**Schemes**

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| GET | `/api/v1/crm/schemes` | `crm.schemes.view` | All active schemes (dealer sees own targets) |
| POST | `/api/v1/crm/schemes` | `crm.schemes.manage` | Create parent-company scheme |
| GET | `/api/v1/crm/schemes/{id}` | `crm.schemes.view` | Scheme detail + dealer attainment list |
| PATCH | `/api/v1/crm/schemes/{id}` | `crm.schemes.manage` | Edit scheme (blocked once DISPATCHING campaigns reference it) |
| POST | `/api/v1/crm/schemes/{id}/targets` | `crm.schemes.manage` | Assign / update dealer targets |
| GET | `/api/v1/crm/schemes/{id}/attainment` | `crm.schemes.view` | Attainment progress per dealer |

**Dealer Sales**

| Method | Path | Permission | Description |
|--------|------|------------|-------------|
| GET | `/api/v1/crm/dealer-sales` | `crm.sales.view` | Aggregated list; dealers see own, admins see all |
| GET | `/api/v1/crm/dealer-sales/{dealer_id}/graph` | `crm.sales.view` | Daily series for chart rendering (§9.5) |
| GET | `/api/v1/crm/dealer-sales/leaderboard` | `crm.sales.view` | Ranked dealer list by batteries delivered this month |

### Web CRM Routes — `/web/crm/*`

| Method | Path | Description |
|--------|------|-------------|
| GET | `/web/crm/customers` | Customer list & search |
| GET/POST | `/web/crm/leads` | Kanban pipeline board |
| GET/POST | `/web/crm/campaigns` | Campaign builder UI |
| GET | `/web/crm/campaigns/{id}/analytics` | Campaign performance dashboard |
| GET/POST | `/web/crm/schemes` | Scheme management + dealer target grid |
| GET | `/web/crm/dealer-sales` | Dealer sales graph + leaderboard |

### Public Tracking Routes — No Authentication Required

> **Middleware stack:** `RateLimitMiddleware` only (no auth, no tenant session required).  
> Tenant is resolved from the token / ticket number itself — NOT from a subdomain or JWT.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/track/{token}` | HTML repair status page — renders progress timeline for the customer |
| POST | `/track/lookup` | Accept `ticket_number` in body → resolve token → 302 redirect to `/track/{token}` |
| GET | `/api/v1/track/{token}` | JSON tracking payload — for WhatsApp bot, mobile app, future integrations |
| GET | `/web/track/{token}` | Alias of `/track/{token}` when deployed on same web domain |

> **Security:** All four routes served over HTTPS only (`Strict-Transport-Security` enforced). Token is 256-bit random — brute-force infeasible. Rate-limiting: `/track/lookup` → max 10 requests / IP / 15 min (TABLE 52). Direct `/track/{token}` reads are not rate-limited (token already provides adequate access control).

### Web Routes — `/web/*` (PHP Session + CSRF)

> **Middleware stack:** `WebAuthMiddleware` (session) → `CsrfMiddleware` → `RoleMiddleware` → Controller  
> These render HTML views; identical business logic, different auth guard.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/web/login` | Login page |
| POST | `/web/auth/send-otp` | OTP send (session flow) |
| POST | `/web/auth/verify-otp` | OTP verify + session create |
| GET/POST | `/web/claims/*` | Full claim CRUD (web panel) |
| GET/POST | `/web/driver/*` | Driver UI pages |
| GET/POST | `/web/service/*` | Service centre pages |
| GET/POST | `/web/tally/*` | Tally import/export UI |
| GET | `/web/reports/*` | Report pages |
| GET/POST | `/web/settings` | Settings UI |



## 7. JS: Client-Side Image Compression

**File:** `public/assets/js/compress.js`

```javascript
/**
 * compress.js
 * Client-side image compression to WebP via Canvas API.
 * Called before any photo upload (orange-tick, skip, handshake).
 *
 * Usage:
 *   import { compressImage } from './compress.js';
 *   const file = await compressImage(inputFile);
 *   formData.append('photo', file);
 */

const DEFAULTS = {
  maxWidth:  1200,        // px — downsample if wider
  maxHeight: 1200,        // px — maintain aspect ratio
  quality:   0.82,        // WebP quality 0–1
  mimeType:  'image/webp',
};

/**
 * @param {File} file          - Original File from <input type="file">
 * @param {object} [opts]      - Override DEFAULTS
 * @returns {Promise<File>}    - Compressed WebP File
 */
export async function compressImage(file, opts = {}) {
  const cfg = { ...DEFAULTS, ...opts };

  return new Promise((resolve, reject) => {
    // Reject non-image MIME types immediately
    if (!file.type.startsWith('image/')) {
      reject(new TypeError(`Expected image, got ${file.type}`));
      return;
    }

    const reader = new FileReader();

    reader.onload = ({ target }) => {
      const img = new Image();

      img.onload = () => {
        let { width, height } = img;

        // Scale down proportionally if over limits
        if (width > cfg.maxWidth) {
          height = Math.round((height * cfg.maxWidth) / width);
          width  = cfg.maxWidth;
        }
        if (height > cfg.maxHeight) {
          width  = Math.round((width * cfg.maxHeight) / height);
          height = cfg.maxHeight;
        }

        const canvas = document.createElement('canvas');
        canvas.width  = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0, width, height);

        canvas.toBlob(blob => {
          if (!blob) {
            reject(new Error('canvas.toBlob() returned null'));
            return;
          }

          // Replace extension with .webp
          const name = file.name.replace(/\.[^.]+$/, '.webp');
          const compressed = new File([blob], name, {
            type:         cfg.mimeType,
            lastModified: Date.now(),
          });

          resolve(compressed);
        }, cfg.mimeType, cfg.quality);
      };

      img.onerror = () => reject(new Error('Image decode failed'));
      img.src = target.result;
    };

    reader.onerror = () => reject(new Error('FileReader failed'));
    reader.readAsDataURL(file);
  });
}

/** Human-readable byte size */
export function formatBytes(bytes) {
  if (bytes < 1024)        return `${bytes} B`;
  if (bytes < 1_048_576)   return `${(bytes / 1024).toFixed(1)} KB`;
  return                          `${(bytes / 1_048_576).toFixed(1)} MB`;
}

/**
 * Wire up a file input with live compression preview.
 * @param {HTMLInputElement} input
 * @param {HTMLElement}      previewEl  - <img> tag for preview
 * @param {HTMLElement}      [sizeEl]   - element to show "Before → After" sizes
 * @returns {() => File|null}           - Getter for the compressed file
 */
export function attachCompressPreview(input, previewEl, sizeEl = null) {
  let compressedFile = null;

  input.addEventListener('change', async () => {
    const raw = input.files?.[0];
    if (!raw) return;

    // Disable input during compression
    input.disabled = true;

    try {
      compressedFile = await compressImage(raw);

      // Preview
      previewEl.src    = URL.createObjectURL(compressedFile);
      previewEl.hidden = false;

      // Size comparison
      if (sizeEl) {
        sizeEl.textContent =
          `${formatBytes(raw.size)} → ${formatBytes(compressedFile.size)}`;
      }
    } catch (err) {
      console.error('Compression failed, using original:', err);
      compressedFile = raw;   // Graceful fallback
    } finally {
      input.disabled = false;
    }
  });

  return () => compressedFile;
}
```

**Server-side guard** in `ImageService.php`:
```php
// Validate MIME regardless of client claims
$finfo = new \finfo(FILEINFO_MIME_TYPE);
$mime  = $finfo->file($tmpPath);
if (!in_array($mime, ['image/webp', 'image/jpeg', 'image/png'], true)) {
    throw new ValidationException('Invalid image format');
}
if (filesize($tmpPath) > 2 * 1024 * 1024) {   // 2 MB hard cap
    throw new ValidationException('Image exceeds 2 MB limit');
}
// Decompression bomb guard (§11.16): read pixel dimensions via header ONLY — zero memory allocation.
// An attacker can send a 1KB WebP that decodes to 50000×50000 px (~10GB RAM). getimagesize()
// reads only the file header and never loads pixel data into memory.
$dims = @getimagesize($tmpPath);
if (!$dims || $dims[0] > 4000 || $dims[1] > 4000) {
    throw new ValidationException('Image dimensions must not exceed 4000×4000 px');
}
```

---

## 8. Security Architecture

| Threat | Mitigation |
|---|---|
| SQL Injection | PDO prepared statements throughout; no raw interpolation |
| CSRF | Double-submit CSRF token on all state-changing POST/PUT/DELETE |
| Session Hijacking | `session_regenerate_id(true)` on OTP success **and** any privilege escalation; Secure+HttpOnly+SameSite=Strict cookies |
| OTP Plaintext Leak | `token_hash CHAR(64)` stores SHA-256 only; plaintext OTP never persisted; compared with `hash_equals()` (timing-safe) |
| OTP Brute Force | 5 failed attempts per 10-min window via `login_attempts` table → `AuthException` + `audit_logs` CRITICAL entry (§5.9) |
| Unrestricted Upload | MIME via `finfo`, extension whitelist, randomised storage filename; `public/assets/uploads/.htaccess` blocks script execution |
| Upload Execution Block | `public/assets/uploads/.htaccess`: `php_flag engine off` · `Options -ExecCGI` · `Deny from all`; files served via `FileController::serve()` |
| EXIF / GPS Metadata Leak | Server re-encodes all uploads via GD: `imagewebp(imagecreatefromstring(file_get_contents($tmp)), $dest, 82)` — strips all EXIF |
| IDOR | Every entity fetch checks `tenant_id` + ownership or role before returning data |
| XSS | `htmlspecialchars()` on all output; JSON responses have `Content-Type: application/json` |
| Path Traversal | `basename()` + `realpath()` before any file operation |
| Rate Limiting | Nginx `limit_req_zone` on `/auth/*` + PHP-level `login_attempts` table (5/10-min lockout) |
| Forced Browsing / File Enumeration | Upload files served via `FileController::serve()` with session+ownership check; direct disk URL returns 403 |
| CSV / Excel Injection | Tally CSV: prefix any cell starting with `=`, `-`, `+`, `@` with `\t`; serials are alphanumeric-only by schema |
| Concurrent Race Condition | `SELECT … FOR UPDATE` inside transaction before every `claims.status` update and claim number generation |
| Mass Assignment | Each controller action uses an explicit field whitelist; no direct `$_POST`-to-model binding |
| Lat/Lng Injection | `dealer_lat`/`dealer_lng` validated server-side: lat ∈ [−90, 90], lng ∈ [−180, 180]; stored as `DECIMAL`, never raw string |
| Signature File Reuse | `driver_handshakes.sig_hash CHAR(64)` stores SHA-256 of signature file; duplicate hash on a new handshake is rejected |
| Security Headers | `Content-Security-Policy`, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Strict-Transport-Security` via `public/.htaccess` |
| HTTPS Enforcement | `public/.htaccess` redirects HTTP → HTTPS with 301; HSTS header set |
| JWT Token Security | Access tokens expire in 15 min (RS256 or HS256-SHA512); refresh tokens are opaque, stored hashed in DB, single-use (rotated on each refresh); `alg` header validated — `none` rejected |
| JWT Secret Rotation | `JWT_SECRET` loaded from env/vault; key rotation supported via `kid` claim and versioned secret map in `config/jwt.php` |
| Tenant Data Isolation | Every SQL query auto-injects `tenant_id = TenantContext::id()` via `QueryBuilder::forTenant()`; cross-tenant ID guessing returns 404 (not 403) to avoid tenant enumeration |
| Image Decompression Bomb | `getimagesize()` reads pixel dimensions **header-only** (zero pixel memory) before GD load; images exceeding 4000×4000 px are rejected before any decompression (§11.16) |
| Excel XXE / Zip Bomb | `libxml_disable_entity_loader(true)` before phpspreadsheet; `setReadDataOnly(true)` streaming mode caps peak RAM; prevents XML entity exfiltration and ZIP decompression DoS (§11.18) |
| OTP Double-Verification | Single atomic `UPDATE otp_tokens SET used=1 WHERE … used=0`; `rowCount()===0` short-circuits immediately — two concurrent threads cannot consume the same token (§11.19) |
| CTE Cycle Protection | `SET @@cte_max_recursion_depth = 50` + per-row `WHERE depth < 50` guard before all recursive battery-lineage queries; terminates safely if `mother_battery_id` cycle exists in data (§11.20) |
| Soft-Delete Unique Collision | MySQL 8 expression index `(IF(deleted_at IS NULL, 1, id))` on `(tenant_id, email)` and `(tenant_id, serial_number)`; deleted rows vacate their unique slot, allowing new records with the same identifiers (§11.21) |
| JWT Revocation Cache Volatility | On Redis unavailability the `ApiAuthMiddleware` falls back to synchronous DB check: `auth_refresh_tokens WHERE jti=? AND revoked_at IS NOT NULL`; revoked tokens cannot regain access through a Redis restart (§11.22) |
| Idempotency Race Condition | `IdempotencyMiddleware` atomically inserts a `status='PROCESSING'` stub row before handler execution; a concurrent duplicate hits the UNIQUE KEY and receives `409 Conflict` immediately (§11.17) |

---

## 9. Analytics & Reporting

### 9.1 Lemon Battery Detection

A battery is a **"Lemon"** if its lineage chain has >= 2 replacements.

```sql
SELECT
    root.serial_number       AS mother_serial,
    root.mfg_year,
    root.mfg_week,
    COUNT(b.id) - 1          AS replacement_count
FROM batteries root
JOIN batteries b ON b.mother_battery_id = root.id
GROUP BY root.id
HAVING replacement_count >= 2
ORDER BY replacement_count DESC;
-- For full-depth chains (3+ levels), use the recursive CTE from §5.4
```

### 9.2 Failure by MFG Week/Year

```sql
SELECT
    b.mfg_year,
    b.mfg_week,
    COUNT(*)         AS total_failures,
    ROUND(COUNT(*) / total.total_in_batch * 100, 2) AS failure_rate_pct
FROM   service_jobs sj
JOIN   claims       c  ON c.id        = sj.claim_id
JOIN   batteries    b  ON b.id        = c.battery_id
JOIN   (
    SELECT mfg_year, mfg_week, COUNT(*) AS total_in_batch
    FROM   batteries
    GROUP  BY mfg_year, mfg_week
) total USING (mfg_year, mfg_week)
WHERE  sj.diagnosis = 'REPLACE'
GROUP  BY b.mfg_year, b.mfg_week
ORDER  BY b.mfg_year, b.mfg_week;
```

### 9.3 Monthly Driver Finance Report

```sql
SELECT
    u.name                                  AS driver,
    DATE_FORMAT(di.delivery_date, '%Y-%m')  AS month,
    COUNT(di.id)                            AS total_deliveries,
    SUM(di.amount)                          AS incentive_total_inr,
    SUM(di.is_paid)                         AS paid_count
FROM delivery_incentives di
JOIN users u ON u.id = di.driver_id
WHERE di.delivery_date BETWEEN :from AND :to
GROUP BY di.driver_id, DATE_FORMAT(di.delivery_date, '%Y-%m')
ORDER BY month DESC, incentive_total_inr DESC;
```

### 9.4 Tally Export CSV Format

```
; Tally-compatible semicolon-delimited CSV
; Columns: VoucherType;Date;StockItem;Qty;Rate;Amount;Narration
Stock Journal;{date};{new_serial};1;0;0;Replacement for {old_serial}
```

```php
// TallyService::exportReplacementCSV(DateRange $range): string
// Fetches all replacements in range, formats rows, streams as:
// Content-Type: text/csv; charset=UTF-8
// Content-Disposition: attachment; filename="tally_export_{date}.csv"
```

---

### 9.5 Dealer Sales Graph

**Source table:** `crm_dealer_sales_daily` (TABLE 49) — pre-aggregated nightly by `DealerSalesRollupJob`.

```sql
-- Daily delivery trend for a single dealer (last 90 days)
-- Powers line/bar chart in dealer dashboard and admin overview
SELECT
    sale_date,
    batteries_delivered,
    claims_raised,
    replacements_done,
    incentives_paid,
    active_customers
FROM  crm_dealer_sales_daily
WHERE tenant_id = :tenant_id
  AND dealer_id  = :dealer_id
  AND sale_date >= CURDATE() - INTERVAL 90 DAY
ORDER BY sale_date ASC;

-- Monthly rollup (for bar chart / admin leaderboard)
SELECT
    YEAR(sale_date)  AS yr,
    MONTH(sale_date) AS mo,
    SUM(batteries_delivered) AS total_delivered,
    SUM(claims_raised)       AS total_claims,
    SUM(incentives_paid)     AS total_incentives,
    MAX(active_customers)    AS peak_customers
FROM  crm_dealer_sales_daily
WHERE tenant_id = :tenant_id
  AND dealer_id  = :dealer_id
  AND sale_date >= CURDATE() - INTERVAL 12 MONTH
GROUP BY yr, mo
ORDER BY yr, mo;
```

**Rollup job logic (nightly, 01:30 IST):**
```php
// DealerSalesRollupJob::handle()
// Runs for each tenant_id. Upserts yesterday's row per dealer.
$yesterday = now()->subDay()->toDateString();

$rows = DB::select("
    SELECT
        dh.dealer_id,
        COUNT(DISTINCT dh.id)                         AS batteries_delivered,
        COUNT(DISTINCT cl.id)                         AS claims_raised,
        COUNT(DISTINCT rp.id)                         AS replacements_done,
        COALESCE(SUM(di.amount), 0)                   AS incentives_paid,
        COUNT(DISTINCT dh.customer_phone)             AS active_customers
    FROM driver_handshakes dh
    LEFT JOIN claims       cl ON cl.dealer_id = dh.dealer_id
                              AND DATE(cl.created_at) = :d
    LEFT JOIN replacements rp ON rp.tenant_id = :tid
                              AND DATE(rp.created_at) = :d
    LEFT JOIN delivery_incentives di ON di.driver_id = dh.driver_id
                              AND DATE(di.created_at) = :d
    WHERE dh.tenant_id = :tid
      AND DATE(dh.handshake_at) = :d
    GROUP BY dh.dealer_id
", ['tid' => $tenantId, 'd' => $yesterday]);

foreach ($rows as $row) {
    DB::statement("
        INSERT INTO crm_dealer_sales_daily
          (tenant_id, dealer_id, sale_date, batteries_delivered, claims_raised,
           replacements_done, incentives_paid, active_customers)
        VALUES (:tid, :did, :d, :bd, :cr, :rd, :ip, :ac)
        ON DUPLICATE KEY UPDATE
          batteries_delivered = VALUES(batteries_delivered),
          claims_raised       = VALUES(claims_raised),
          replacements_done   = VALUES(replacements_done),
          incentives_paid     = VALUES(incentives_paid),
          active_customers    = VALUES(active_customers),
          updated_at          = NOW()
    ", (array)$row + ['tid' => $tenantId, 'd' => $yesterday]);
}
```

**API response shape** (for JS charting library):
```json
{
  "series": [
    { "date": "2026-03-01", "delivered": 14, "claims": 2, "incentives_paid": 140.00 },
    { "date": "2026-03-02", "delivered": 19, "claims": 1, "incentives_paid": 190.00 }
  ],
  "meta": { "dealer_id": 7, "period_days": 90, "total_delivered": 412 }
}
```

---

### 9.6 Campaign Performance Analytics

```sql
-- Delivery funnel per campaign
SELECT
    c.id,
    c.name,
    c.channel,
    c.total_recipients,
    c.sent_count,
    c.delivered_count,
    c.opened_count,
    c.clicked_count,
    c.failed_count,
    ROUND(c.delivered_count / NULLIF(c.sent_count, 0) * 100, 1) AS delivery_rate_pct,
    ROUND(c.opened_count    / NULLIF(c.delivered_count, 0) * 100, 1) AS open_rate_pct,
    ROUND(c.clicked_count   / NULLIF(c.opened_count, 0) * 100, 1)   AS click_rate_pct,
    ROUND(c.failed_count    / NULLIF(c.total_recipients, 0) * 100, 1) AS failure_rate_pct
FROM crm_campaigns c
WHERE c.tenant_id = :tenant_id
  AND c.status = 'COMPLETED'
ORDER BY c.completed_at DESC
LIMIT 50;

-- Top-performing campaigns for a date range
SELECT
    c.name,
    c.channel,
    c.clicked_count,
    ROUND(c.clicked_count / NULLIF(c.delivered_count, 0) * 100, 1) AS ctr_pct,
    s.name AS scheme_name
FROM crm_campaigns c
LEFT JOIN crm_schemes s ON s.id = c.scheme_id
WHERE c.tenant_id = :tenant_id
  AND c.dispatched_at BETWEEN :from AND :to
ORDER BY ctr_pct DESC
LIMIT 10;
```

**Stat counters update flow:**  
`CampaignRecipient::updateStatus()` increments the denormalized counter on `crm_campaigns` using `UPDATE ... SET delivered_count = delivered_count + 1` — safe under concurrent delivery webhook callbacks (MySQL atomic increment).

---

### 9.7 Scheme Attainment Dashboard

```sql
-- Per-scheme attainment overview (for CRM Manager / Admin)
SELECT
    s.name                             AS scheme_name,
    s.scheme_code,
    s.valid_from,
    s.valid_to,
    COUNT(t.id)                        AS total_dealers,
    SUM(t.target_hit)                  AS dealers_hit_target,
    ROUND(AVG(
        t.volume_achieved / NULLIF(t.volume_target, 0) * 100
    ), 1)                              AS avg_attainment_pct,
    SUM(t.volume_achieved)             AS total_units_sold,
    SUM(t.revenue_achieved)            AS total_revenue_inr
FROM  crm_schemes s
JOIN  crm_scheme_dealer_targets t ON t.scheme_id = s.id
WHERE s.tenant_id = :tenant_id
  AND s.is_active = 1
GROUP BY s.id
ORDER BY s.valid_to ASC;

-- Per-dealer attainment for a specific scheme
SELECT
    u.name                             AS dealer_name,
    t.volume_target,
    t.volume_achieved,
    ROUND(t.volume_achieved / NULLIF(t.volume_target, 0) * 100, 1) AS attainment_pct,
    t.incentive_on_hit                 AS bonus_inr,
    t.target_hit,
    t.target_hit_at
FROM  crm_scheme_dealer_targets t
JOIN  users u ON u.id = t.dealer_id
WHERE t.scheme_id = :scheme_id
  AND t.tenant_id = :tenant_id
ORDER BY attainment_pct DESC;
```

---

## 10. Deployment Notes

```
Web Server:   Nginx + PHP 8.2-FPM
Database:     MySQL 8.0+ (innodb_buffer_pool_size >= 256M for production)
Redis:        redis-server >= 7.x; used for queue backend + settings cache + session cache (optional)
PHP Ext:      pdo_mysql, fileinfo, gd or imagick, mbstring, openssl, redis (phpredis)
Composer:     phpoffice/phpspreadsheet ^2.0 (Tally), phpmailer/phpmailer ^6.8 (OTP),
              firebase/php-jwt ^6 (JWT auth), predis/predis ^2 (Redis client)
Timezone:     mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql
              Connection.php: SET time_zone = 'Asia/Kolkata' on every new PDO connection.
```

### Cron Jobs

```
* * * * *    php /var/www/bin/process-email-queue.php   # Legacy fallback if QUEUE_DRIVER=db
0 0 * * *    php /var/www/bin/nightly-audit-reminder.php # EOD scan flag
30 1 * * *   php /var/www/bin/crm-sales-rollup.php       # DealerSalesRollupJob (01:30 IST)
0  2 * * 0   php /var/www/bin/crm-churn-detection.php    # ChurnDetectionJob weekly (Sunday 02:00 IST)
0  3 * * *   php /var/www/bin/crm-scheme-attainment.php  # SchemeService::checkAttainment() nightly
```

### Queue Workers (Supervisor — when `QUEUE_DRIVER=redis`)

```ini
; /etc/supervisor/conf.d/battery-worker.conf
[program:battery-worker]
command=php /var/www/bin/worker.php --queues=emails,reports,tally,crm
numprocs=2
autostart=true
autorestart=true
stdout_logfile=/var/log/battery-worker.log
```

```bash
# Manual start (development)
php bin/worker.php --queues=emails,reports,tally,crm --sleep=1 --max-jobs=500
```

### Environment Variables (`.env.example`)

```dotenv
# App
APP_NAME="Battery Management"
APP_ENV=production          # local | staging | production
APP_URL=https://app.battery-mgmt.com
APP_TIMEZONE=Asia/Kolkata

# Database
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=battery_db
DB_USER=app_user
DB_PASS=

# Database Read Replica (Phase 3 — optional)
DB_READ_HOST=

# Redis
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# Queue
QUEUE_DRIVER=redis          # redis | db (db = fallback, uses email_queue table)
QUEUE_DEFAULT=emails

# Storage
STORAGE_DRIVER=local        # local | s3 | r2
S3_KEY=
S3_SECRET=
S3_BUCKET=
S3_REGION=ap-south-1
S3_ENDPOINT=                # leave blank for AWS; set for Cloudflare R2

# JWT
JWT_SECRET=                 # min 64 random bytes (openssl rand -hex 64)
JWT_ACCESS_TTL=900          # seconds (15 min)
JWT_REFRESH_TTL=2592000     # seconds (30 days)

# Mail
MAIL_HOST=smtp.gmail.com
MAIL_PORT=587
MAIL_USER=
MAIL_PASS=
MAIL_FROM=no-reply@battery-mgmt.com
MAIL_FROM_NAME="Battery Management"

# CRM — Campaign Email
MAIL_RATE_PER_MIN=200         # campaign blast throttle (emails/min per tenant)
MAIL_UNSUBSCRIBE_SECRET=      # min 32 random bytes — HMAC salt for unsubscribe tokens
CAMPAIGN_FROM_NAME=           # defaults to APP_NAME if blank
CAMPAIGN_FROM_EMAIL=          # defaults to MAIL_FROM if blank

# CRM — WhatsApp (Phase 3)
WA_BSP_PROVIDER=              # twilio | gupshup | meta_cloud (leave blank to disable WA campaigns)
WA_API_KEY=
WA_PHONE_NUMBER_ID=           # BSP registered number ID
WA_RATE_PER_MIN=80            # messages/min (BSP tier limit)
WA_TEMPLATE_NAMESPACE=        # pre-approved BSP message template namespace
```

### Upload & Symlink Setup

```bash
# Symlink storage to web-accessible path
ln -s /var/www/storage/uploads /var/www/public/assets/uploads
chown -R www-data:www-data /var/www/storage/
chmod 750 /var/www/storage/uploads/

# Verify .htaccess is in place (blocks direct file access)
cat /var/www/public/assets/uploads/.htaccess
# → Deny from all
# → php_flag engine off
# → Options -ExecCGI
```

```
Session:      php.ini: session.cookie_secure=1, session.cookie_httponly=1,
                       session.cookie_samesite=Strict, session.use_strict_mode=1
Session GC:   Cron or php.ini gc_probability=1, gc_maxlifetime=7200 to prune sessions table
HTTPS:        Required. OTP over HTTP is a credential interception risk. Enforce via .htaccess RewriteRule.
```

---

## 11. Deep Risk Register — Additional Vulnerabilities Found

The following risks were identified during deep architectural review beyond the initial 12-point audit. Each entry states the **Leakage Path**, **Business Impact**, and **Fix**.

---

### 11.1 Unauthenticated Direct File Access (Forced Browsing)

| | |
|---|---|
| **Leakage Path** | `public/assets/uploads/` is a symlink to `storage/uploads/`. Any file (dealer signatures, customer photos, handshake images) is directly accessible by URL if the attacker guesses the filename (e.g., `handshakes/2026-04-04_ABC123.webp`). |
| **Business Impact** | PII leak: customer photos, dealer signatures, GPS-tagged images exposed without authentication. |
| **Fix** | `public/assets/uploads/.htaccess`: `Deny from all`. All files served via `FileController::serve($path)` which checks session + resource ownership before calling `readfile()`. |

---

### 11.2 Driver Handshake ↛ Task Linkage Gap

| | |
|---|---|
| **Leakage Path** | `driver_handshakes` links to `route_id` + `dealer_id` only. A driver could complete a handshake for Dealer A's tasks and retroactively mark Dealer B's tasks as `DONE`, then claim incentives without a matching handshake. |
| **Business Impact** | Incentive fraud; broken audit trail. |
| **Fix** | Add pivot table `handshake_tasks (handshake_id INT UNSIGNED NOT NULL, task_id INT UNSIGNED NOT NULL UNIQUE)`. `IncentiveService` must JOIN through this pivot to validate the specific task–handshake link (§5.10 `handshake_id` FK is the minimum fix; pivot table gives full provability). |

---

### 11.3 Multiple Active OTPs — Token Accumulation

| | |
|---|---|
| **Leakage Path** | Each "Resend OTP" click inserts a new token row without invalidating prior ones. If a user clicks Resend 10 times, there are 10 valid 6-digit tokens simultaneously — multiplying the brute-force window 10×. |
| **Business Impact** | Attacker has 10 chances per OTP generation cycle before the rate-limit kicks in. |
| **Fix** | `AuthService::sendOtp()` must run `UPDATE otp_tokens SET used=1 WHERE user_id=? AND used=0` **before** inserting the new token. Ensures only one active token exists per user at any time. |

---

### 11.4 Concurrent Claim Status Race (Double Transition)

| | |
|---|---|
| **Leakage Path** | Two simultaneous HTTP requests (two browser tabs, or a double-tap on mobile) both read `status='DIAGNOSED'` and both attempt `REPLACED` transition before either commits — resulting in two `replacements` rows for one claim. |
| **Business Impact** | Battery lineage corruption; two new battery serials assigned as replacements for one claim. |
| **Fix** | `ClaimService::transition()` (§5.7) uses `SELECT … FOR UPDATE` inside a transaction. The second request blocks, then reads `status='REPLACED'`, fails the `ALLOWED` map check, and throws `BusinessRuleException`. |

---

### 11.5 EXIF / GPS Metadata in Uploaded Images

| | |
|---|---|
| **Leakage Path** | Photos taken on smartphones embed GPS coordinates, device serial numbers, and timestamps in EXIF metadata — even after client-side WebP compression (Canvas API does NOT strip EXIF). |
| **Business Impact** | Customer location data inferred from EXIF. PII leak. Potential DPDP Act (India) compliance violation. |
| **Fix** | `ImageService.php`: after MIME validation, re-encode via GD: `imagewebp(imagecreatefromstring(file_get_contents($tmp)), $destPath, 82)`. GD strips all EXIF on re-encode. |

---

### 11.6 CSV / Excel Injection in Tally Export

| | |
|---|---|
| **Leakage Path** | If `customer_name`, `complaint`, or `narration` fields contain `=SUM(...)` or `=cmd\|' /C calc'!A0`, a Tally operator opening the exported CSV in Excel may execute arbitrary formulas or OS commands. |
| **Business Impact** | Remote Code Execution on the finance operator's machine when the export is opened. |
| **Fix** | `TallyService::exportReplacementCSV()`: sanitize every text cell — if the value starts with `=`, `-`, `+`, or `@`, prefix with `\t`. Serial columns pass only `^[A-Z0-9]{14,15}$` (already regex-validated on import). |

---

### 11.7 Claim Lock Bypass via `is_locked` Flag

| | |
|---|---|
| **Leakage Path** | `claims.is_locked = 1` is the sole guard preventing edits post-driver-receipt. A bug, direct DB edit, or future migration that resets `is_locked = 0` silently re-opens the claim for editing. |
| **Business Impact** | Dealers could change battery serial or customer address after the driver has physically collected the unit — enabling fraud and mismatched returns. |
| **Fix** | Status-based lock (§5.3): `ClaimController::update()` checks `status NOT IN ('DRAFT','SUBMITTED')` and throws regardless of `is_locked`. Retain `is_locked` as a UX hint only. |

---

### 11.8 Hard Delete of Users Destroys Audit Trail

| | |
|---|---|
| **Leakage Path** | `audit_logs.user_id` is `ON DELETE SET NULL`. Deleting an active user sets all their audit records to `user_id = NULL` — making it impossible to attribute who performed historical actions. |
| **Business Impact** | Fraud investigations fail; "ghost" audit events with no owner. |
| **Fix** | Never hard-delete users. `UserController` must only set `is_active = 0`. Remove `ON DELETE CASCADE` on `otp_tokens` (replace with `ON DELETE RESTRICT`; invalidate tokens before deactivation). |

---

### 11.9 Signature File Path Reuse (Driver Fraud)

| | |
|---|---|
| **Leakage Path** | `driver_handshakes.dealer_signature` stores a file path. A driver could POST the path of a previously collected signature to create a new handshake record without re-collecting the dealer's live signature. |
| **Business Impact** | Driver submits fake handshakes using recycled signature files to claim delivery incentives for deliveries that never happened. |
| **Fix** | Add `sig_hash CHAR(64) NOT NULL` to `driver_handshakes`. Server computes `hash('sha256', file_get_contents($tmp))`. Before `INSERT`, check `SELECT id FROM driver_handshakes WHERE sig_hash = ?` — reject if already used. |

---

### 11.10 Session Table Unbounded Growth

| | |
|---|---|
| **Leakage Path** | `sessions` table grows indefinitely if PHP's session GC is disabled (`session.gc_probability = 0`), which is the default in many Nginx+PHP-FPM setups where file session GC is handled externally. |
| **Business Impact** | Table bloat → login queries degrade; disk exhaustion on high-traffic deployments. |
| **Fix** | Cron: `DELETE FROM sessions WHERE last_activity < DATE_SUB(NOW(), INTERVAL 2 HOUR);` (every 30 min). Or set `session.gc_probability = 1`, `session.gc_maxlifetime = 7200` in `php.ini`. |

---

### 11.11 Paginated API List Endpoints Missing

| | |
|---|---|
| **Leakage Path** | `GET /claims` with no pagination returns all rows in a single response. At 100k+ records, this exhausts PHP memory and exposes a full data dump to any authenticated LIST-role user. |
| **Business Impact** | DoS via normal usage pattern; full data exfiltration by a rogue employee. |
| **Fix** | All list endpoints enforce `LIMIT`/`OFFSET`: default `per_page=25`, max `per_page=100`. Response envelope: `{ "data": [...], "meta": { "page": 1, "per_page": 25, "total": 48231 } }` |

---

### 11.12 Timezone Inconsistency in DATE Columns

| | |
|---|---|
| **Leakage Path** | `delivery_date DATE` is set by `CURDATE()` / PHP `date('Y-m-d')`. If the server is UTC and the business is IST (+5:30), a delivery at 12:05 AM IST = 6:35 PM UTC of the **previous** day — misassigning it to yesterday's incentive report. |
| **Business Impact** | Driver incentive underpayment / wrong-month attribution. |
| **Fix** | `Connection.php` MUST run `SET time_zone = 'Asia/Kolkata'` at the start of every PDO connection. Pre-load timezone data: `mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql`. Verify: `SELECT NOW(), @@session.time_zone;` |

---

### 11.13 Missing HTTPS Enforcement in `.htaccess`

| | |
|---|---|
| **Leakage Path** | If Nginx does not redirect HTTP→HTTPS, OTP codes and session cookies can be sent over plaintext HTTP on the same network (coffee shop, shared office LAN). |
| **Business Impact** | OTP interception; session cookie theft; account takeover. |
| **Fix** | `public/.htaccess`: `RewriteCond %{HTTPS} off` → `RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [R=301,L]`. Add header: `Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"` |

---

### 11.14 Missing Composite Index on `batteries (is_in_tally, status)`

| | |
|---|---|
| **Leakage Path** | The Lemon Battery report (§9.1) and the Tally UPSERT (§5.11) both query `batteries WHERE is_in_tally = ? AND status = ?`. No composite index exists — full table scan at scale. |
| **Business Impact** | Tally import of 10k+ rows becomes O(n²); UI tally dashboard times out. |
| **Fix** | `ALTER TABLE batteries ADD INDEX idx_tally_status (is_in_tally, status);` |

---

### 11.15 Driver Handshake Timestamp Integrity

| | |
|---|---|
| **Leakage Path** | `handshake_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP` is server-set, but the client JS `Date.now()` may diverge significantly (driver's phone clock wrong). No cross-check is performed, making forensic timestamp disputes unreliable. |
| **Business Impact** | Driver claims a delivery at 10am; server-side evidence shows 7pm. Dispute resolution fails. |
| **Fix** | Log both timestamps: add `client_timestamp BIGINT NULL` (JS `Date.now()`/1000 epoch) alongside `handshake_at`. If `ABS(UNIX_TIMESTAMP(handshake_at) - client_timestamp) > 300` (5 min), insert an `audit_logs` entry with `severity='MEDIUM'`. |

---

### 11.16 Image Decompression Bomb (Pixel Flood)

| | |
|---|---|
| **Leakage Path** | To strip EXIF data, `ImageService.php` uses GD (`imagecreatefromstring`). While the system strictly limits the *file size* to 2MB, an attacker can craft a highly compressed WebP or PNG image that contains enormous internal pixel dimensions (e.g., 50,000 x 50,000 pixels). When loaded via GD, the system immediately attempts to decompress it into uncompressed RAM (which would take ~10GB). |
| **Business Impact** | Immediate PHP-FPM process crash / Server Out-of-Memory (OOM) leading to severe Denial of Service (DoS) across all tenants. |
| **Fix** | Before loading the image into memory with GD, read the header sizes using `getimagesize()`. Hard-reject any image with dimensions safely exceeding typical camera outputs (e.g., width > 4000 or height > 4000). |

---

### 11.17 Idempotency Key Race Condition

| | |
|---|---|
| **Leakage Path** | The idempotency middleware relies on saving the *completed HTTP response* to `api_idempotency_keys`. If two exact duplicate requests hit the database at perfectly identical timestamps, the middleware will do a `SELECT` and find nothing for *both* threads. Both will process the heavy operation, execute effects, and potentially trigger a DB constraint collision downstream. |
| **Business Impact** | Double incentive dispatch, duplicate billing, or duplicate claims breaking the tenant sequence. |
| **Fix** | Alter the middleware to execute an atomic `INSERT` of an "In Flight" record into `api_idempotency_keys` with a `202 Processing` response code *before* passing the request to the controller. A concurrent request will see this active lock and immediately return a `409 Conflict`. |

---

### 11.18 Tally Excel Import XXE & Zip Bomb Attacks

| | |
|---|---|
| **Leakage Path** | The system relies on parsing Tally Excel files via queue workers. Because modern `.xlsx` files are intrinsically XML files stored in a ZIP archive, the upload is vulnerable to XML External Entity (XXE) data exfiltration and Zip Decompression Bombs. |
| **Business Impact** | Remote Code Execution (RCE) via `phpspreadsheet`, Server-Side Request Forgery (SSRF), or a complete disk/memory wipe of the Supervisor worker. |
| **Fix** | Enforce `libxml_disable_entity_loader(true);` before parsing the Excel document (disables XXE) and enforce strict streaming limits rather than loading entire sheets into RAM simultaneously. |

---

### 11.19 Concurrent OTP Double-Verification

| | |
|---|---|
| **Leakage Path** | The document specifies checking the OTP with `hash_equals()`. If the system reads the OTP, passes `hash_equals()`, and *then* attempts `UPDATE otp_tokens SET used = 1`, two concurrent HTTP calls with the same valid OTP can bypass the check instantaneously before the `used` flag commits. |
| **Business Impact** | Issuance of two valid JWT token pairs for a single successful OTP authentication event, cloning the active session. |
| **Fix** | Transform the verification step into a single atomic sequence. Execute the update immediately: `UPDATE otp_tokens SET used = 1 WHERE user_id = ? AND token_hash = ? AND used = 0 AND expires_at > NOW()`. If `rowCount() === 1`, proceed to issue the JWT. |

---

### 11.20 Recursive CTE Infinite Loop (Lineage Break)

| | |
|---|---|
| **Leakage Path** | The recursive query used to find battery lineage uses `WITH RECURSIVE lineage AS (...)`. If a database glitch or manual migration creates a cycle in `mother_battery_id` (e.g., A -> B -> C -> A), the SQL constraint doesn't block it natively. The CTE will recurse infinitely upon the first query, locking the connection pool. |
| **Business Impact** | Database query timeout and thread exhaustion (Denial of Service). |
| **Fix** | Add hard cycle protection inside the CTE. MySQL 8.0 allows `LIMIT 100` inside recursions, or building a path tracker `CONCAT(path, ',', id)` and enforcing `WHERE id NOT IN (path)` throughout the loop. |

---

### 11.21 Soft Delete Unique Key Collision

| | |
|---|---|
| **Leakage Path** | The design states `deleted_at TIMESTAMP NULL` for soft deletes and that "the unique fields remain reserved". Therefore, if the tenant administrator deletes a user due to an HR issue, and a year later tries to provision a *new* account for them, Table 1's `UNIQUE KEY uq_tenant_email (tenant_id, email)` will indefinitely block the creation. |
| **Business Impact** | Poor SaaS UX, forcing the SaaS operator to do manual database operations (DBA script drops) to clear out inactive constraints. |
| **Fix** | Upgrade to MySQL 8.0's functional/expression indexes. Redefine the constraint as: `UNIQUE KEY idx_tenant_email_live (tenant_id, email, (IF(deleted_at IS NULL, 1, id)))`. This enables soft-deleted records to step natively out of the uniqueness envelope. |

---

### 11.22 JWT Revocation Cache Volatility

| | |
|---|---|
| **Leakage Path** | Access token invalidation (`jti` blocklists) are stored in Redis caching (`SET jwt:revoked:{jti}`). If the Redis instance restarts unexpectedly or drops keys due to maxmemory policies, all previously blocked `jti` lists vanish. |
| **Business Impact** | Revoked (logged-out) access tokens instantly regain their validity for up to 15 minutes, neutralizing immediate lockdown capabilities. |
| **Fix** | If highly sensitive operations are at risk, fall back to checking the DB's `auth_refresh_tokens` list synchronously, or accept the cache-volatility as a defined risk tolerance. |

---

## 12. SaaS Architecture & Upgrade Roadmap

---

### 12.1 Service Contracts (Interface-First Design)

All domain services are bound through interfaces. See §5.13 for full interface definitions.

| Interface | Concrete (Phase 1) | Swap Target |
|---|---|---|
| `ClaimServiceInterface` | `ClaimService` | Microservice endpoint (Phase 4) |
| `BatteryServiceInterface` | `BatteryService` | — |
| `StorageDriver` | `LocalStorageDriver` | `S3StorageDriver` / `R2StorageDriver` |
| `QueueDriverInterface` | `RedisQueueDriver` | `DatabaseQueueDriver` (fallback) |
| `AuthServiceInterface` | `AuthService` | — |
| `TenantServiceInterface` | `TenantService` | — |

---

### 12.2 Storage Abstraction Layer

```
STORAGE_DRIVER=local → LocalStorageDriver  → storage/uploads/{tenant_id}/{entity_type}/
STORAGE_DRIVER=s3    → S3StorageDriver     → s3://{S3_BUCKET}/{tenant_id}/{entity_type}/
STORAGE_DRIVER=r2    → R2StorageDriver     → Cloudflare R2 (S3-compatible, cheaper egress)
```

- All drivers implement `StorageDriver::put()`, `getSignedUrl()`, `delete()`
- `files` table (TABLE 28) tracks `storage_driver + disk_path` — switching drivers mid-run is non-destructive (old files retain their original driver reference)
- Signed URLs expire in `STORAGE_SIGNED_URL_TTL` seconds (default 3600)
- `FileController::serve()` calls `StorageDriver::getSignedUrl()` and returns a temporary redirect — no file bytes flow through PHP in production

---

### 12.3 Event System

```php
// Dispatch a domain event
EventBus::dispatch(new ClaimStatusChanged($claim, $oldStatus, $newStatus, $actorId));

// Listeners registered in bootstrap/events.php
EventBus::listen(ClaimStatusChanged::class, [
    WriteClaimStatusHistory::class,   // always
    NotifyOnClaimChange::class,       // always — injects tracking URL (§5.22, §14.4)
    AuditClaimChanges::class,         // always
    TriggerIncentiveOnHandshake::class, // only if transition = DELIVERED
]);

// Also register for ClaimCreated so the welcome email includes tracking URL
EventBus::listen(ClaimCreated::class, [
    NotifyOnClaimChange::class,       // sends dealer + customer confirmation with tracking link
]);
```

**Core domain events:**

| Event | Fired by | Listeners |
|---|---|---|
| `ClaimCreated` | `ClaimService::create()` | Audit, Notify dealer |
| `ClaimStatusChanged` | `ClaimService::transition()` | StatusHistory, Audit, Notify |
| `BatteryInwarded` | `ServiceJobService::inward()` | Audit, Notify dispatch mgr |
| `DiagnosisCompleted` | `ServiceJobService::diagnose()` | Audit, Notify dealer |
| `ReplacementAssigned` | `ReplacementService::assign()` | Audit, Trigger REPLACED state |
| `HandshakeCaptured` | `DriverService::handshake()` | Incentive record, Audit |
| `DriverTaskCompleted` | `DriverService::completeTask()` | Route progress update, Audit |
| `UserLoggedIn` | `AuthService::verifyOtp()` | Reset `login_attempts`, Audit |
| `TallyImportCompleted` | `TallyService::processImport()` | Audit, Notify admin |

---

### 12.4 Redis Queue System

```
Queue names:
  emails     — OTP + notifications (high priority, 2 workers)
  tally      — Large Tally import jobs (1 worker, unbounded runtime)
  reports    — Finance / analytics report generation (1 worker)
  default    — Everything else
```

**Job lifecycle:**

```
Dispatch → Redis LPUSH {queue} → Worker BRPOP → execute()
                                        ↓ fail?
                               retry (max 3) → dead-letter queue
```

**Sample job:**

```php
// app/Modules/Notifications/Jobs/SendOtpEmailJob.php
class SendOtpEmailJob {
    public function __construct(
        private readonly string $to,
        private readonly string $otpPlaintext,   // used only here; never stored
        private readonly int    $tenantId,
    ) {}

    public function handle(EmailChannel $emailChannel): void {
        TenantContext::setById($this->tenantId);      // restore tenant context for worker thread
        $emailChannel->sendOtp($this->to, $this->otpPlaintext);
    }
}
```

---

### 12.5 JWT Authentication

```
Access token:  HS256-SHA512 · 15 min TTL · payload: {sub, tenant_id, role_ids, iat, exp, jti}
Refresh token: Opaque 64-byte random · 30-day TTL · stored as SHA-256 hash in
               `auth_refresh_tokens` table (TABLE 31). Single-use: each refresh
               call rotates the token (old row's revoked_at is set; new row inserted).

> **Storage split:**
> - **Web/PHP sessions** → `sessions` table (TABLE 16) — Laravel-style payload blob, no token_hash
> - **API refresh tokens** → `auth_refresh_tokens` table (TABLE 31) — hashed opaque token, per-device
```

**Token issuance flow:**

```
POST /api/v1/auth/verify-otp
  → AuthService::verifyOtp($email, $otp)
     1. Hash incoming OTP: $hash = hash('sha256', $inputOtp)
     2. Atomic consume — prevents double-verification (§11.19):
          UPDATE otp_tokens SET used = 1
          WHERE  user_id = :uid AND token_hash = :hash
                 AND used = 0 AND expires_at > NOW()
          → rowCount() === 0  ⟹  invalid / expired / already used → AuthException
          → rowCount() === 1  ⟹  token consumed; exactly one thread proceeds
     (Note: hash_equals() is NOT used here — the atomic UPDATE IS the comparison.)
  → CleanUp login_attempts
  → JwtService::issue($user, $tenant)
     → accessToken  (signed JWT, 15 min)
     → refreshToken (random_bytes(64), stored hashed in auth_refresh_tokens)
  → Response: { access_token, refresh_token, expires_in: 900 }
```

**Refresh flow:**

```
POST /api/v1/auth/refresh
  body: { refresh_token: "..." }
  → Hash incoming token with SHA-256
  → SELECT * FROM auth_refresh_tokens
      WHERE token_hash = ? AND expires_at > NOW() AND revoked_at IS NULL
  → UPDATE auth_refresh_tokens SET revoked_at = NOW() WHERE id = ?
  → INSERT INTO auth_refresh_tokens (new row with new token_hash, new expires_at)
  → JwtService::issue() → new access + refresh pair
```

**Rejection rules enforced in `ApiAuthMiddleware`:**

- `alg: none` → reject immediately  
- Expired `exp` → 401 (client must refresh)  
- Missing `tenant_id` claim → 401  
- `jti` in revocation list: check Redis `SET jwt:revoked:{jti}` (TTL = remaining exp) first; on Redis unavailability **fall back to** synchronous DB check `SELECT 1 FROM auth_refresh_tokens WHERE jti = ? AND revoked_at IS NOT NULL` — revocation is never bypassed through a cache restart (§11.22) → 401

---

### 12.6 Upgrade Roadmap

#### Phase 1 — SaaS Foundation *(Build with the system from Day 1)*

| Item | What |
|------|------|
| Multi-tenancy DB | `tenants`, `plans`, `tenant_settings`, `tenant_sequences` tables; `tenant_id` on all 21 operational tables |
| Modular folders | `app/Modules/*/` structure as in §3 |
| JWT auth | `JwtService`, `ApiAuthMiddleware`, `/api/v1/auth/*` routes |
| Service interfaces | Bind all 6 interfaces in `bootstrap/bindings.php` |
| Storage abstraction | `StorageDriver` interface + `LocalStorageDriver`; `files` table |
| Tenant middleware | `TenantMiddleware` + `TenantContext` injected into `QueryBuilder` |
| RBAC tables | `roles`, `permissions`, `role_permissions`, `user_roles` (replaces ENUM `users.role`) |
| Batteries lineage | `root_battery_id`, `lineage_depth`, `replacement_count` columns |
| Migration files | `022–030` for all new tables |

#### Phase 2 — Platform Hardening *(First 3 months after launch)*

| Item | What |
|------|------|
| Redis queue | `RedisQueueDriver` + `bin/worker.php` + Supervisor config |
| Event system | `EventBus::dispatch()` + all 9 core domain events + listeners |
| **Optimistic locking** | Add `version_no INT UNSIGNED DEFAULT 1` to `claims`, `service_jobs`, `tenant_settings`, `users`. PUT endpoints reject with HTTP 409 if `version_no` in body ≠ DB row. |
| **Soft delete framework** | Add `deleted_at TIMESTAMP NULL` + `deleted_by INT UNSIGNED NULL` to `users`, `claims`, `files`, `tenants`. All queries filter `WHERE deleted_at IS NULL`. Monthly purge cron permanently removes rows older than the data-retention policy. **Unique-key policy (§11.21):** MySQL 8 expression indexes `(IF(deleted_at IS NULL, 1, id))` are used on `(tenant_id, email)` and `(tenant_id, serial_number)` so soft-deleted rows vacate their unique slot — a new record with the same email or serial can be created immediately after deletion. Resurrection of an existing record is `UPDATE … SET deleted_at = NULL` (not a new INSERT). Hard-delete is permanently forbidden on tables with audit-trail dependents (§11.8). |
| **PlanGuard enforcement** | `PlanGuard::check($tenant, $permission)` before claim create, user invite, bulk export, and API access. Returns 429 with `X-Plan-Limit` header on quota breach. |
| **Idempotency middleware** | `IdempotencyMiddleware` checks `api_idempotency_keys` (TABLE 34) on 7 critical POST routes: `/claims`, `/handshakes`, `/replacements`, `/incentives/payout`, `/auth/refresh`, `/tally/import`, `/eod/submit`. On first request, atomically inserts a `status='PROCESSING'` stub row before handing off to the controller — a racing duplicate hits the UNIQUE KEY and immediately receives `409 Conflict` (§11.17). On handler completion the row is updated to `status='COMPLETE'` with the cached response. Replays cached response on retry within 24 h. |
| Request IDs | `X-Request-ID` header on every response; propagated to `audit_logs.request_id`, queue job payloads, and outbox events. Every structured log line MUST include `{request_id, tenant_id, user_id, duration_ms}`. |
| Report snapshots | Async `GenerateReportJob` → write to `files` table; expire old snapshots |
| Feature flags | `tenant_settings` key `feature.{name}` → FeatureFlagService |
| Observability | Structured JSON logs → stdout; ERROR events fire `audit_logs CRITICAL`; health endpoints `/api/v1/health/live` + `/api/v1/health/ready`. **Minimum metric set to instrument:** queue lag (PENDING outbox rows older than 30 s), OTP failure rate (per tenant per hour), virus-scan backlog (PENDING files older than 5 min), idempotency replay rate (replays / total requests), refresh-token rotation failures (revoked_at set without new row). |

#### Phase 3 — Mobile & Scale *(6–12 months)*

| Item | What |
|------|------|
| Mobile API hardening | Flutter / React Native clients using `/api/v1/*`; push notification channel (FCM) added to `Notifications` module |
| Mobile offline sync | App queues mutations locally with UUID idempotency keys. On reconnect, POST replay uses idempotency middleware (Phase 2). Conflict policy: server wins on status fields; client wins on GPS / photo fields. |
| S3 / R2 storage | Flip `STORAGE_DRIVER=r2` in `.env`; existing `files` rows retain `storage_driver=local` pointer |
| **Per-tenant secrets** | JWT signing secret, SMTP credentials, and storage credentials stored per tenant in HashiCorp Vault or AWS KMS. `encryption_key_id` on `files` (TABLE 28) references the KMS key wrapping the content key. Onboarding flow auto-generates tenant KMS key. |
| **Read-optimized reporting** | Daily aggregate table `rpt_daily_claims` (tenant_id, date, submitted_count, closed_count, replaced_count). Monthly `rpt_monthly_incentives`. ETL Supervisor worker runs nightly, reducing 30%+ of ad-hoc report load on live tables. |
| Redis cache | Cache tenant settings (TTL 5 min), heavy report queries (TTL 15 min), battery lineage results (TTL 1 min per ID) using tagged cache invalidation |
| MySQL read replica | `DB_READ_HOST` in `.env`; `QueryBuilder` routes `SELECT` to replica, writes to primary |
| API rate limiting | Redis sliding-window counters per `(tenant_id, user_id, route)` — plugged into `ApiAuthMiddleware` |
| Pagination | All list endpoints accept `?page=&per_page=` (max 100); `meta.pagination` in envelope |

#### Phase 4 — Full SaaS Ops *(12+ months)*

| Item | What |
|------|------|
| Billing | Stripe integration; `plans` table drives feature gates; usage events emitted per claim, per delivery |
| Usage metering | Monthly claim counter per tenant checked against `plans.max_monthly_claims` |
| Tenant onboarding | Self-serve wizard: create tenant → choose plan → invite first admin → seed roles |
| OpenAPI / Swagger | `openapi.yaml` auto-generated from route annotations; published at `/api/v1/docs` |
| White-labelling | Per-tenant logo, colors, email sender name stored in `tenant_settings` |
| Module extraction | High-traffic modules (Notifications, Reports) extracted to micro-services communicating via Redis Pub/Sub |

---

### 12.7 Recommended Final Tech Stack

| Layer | Technology | Notes |
|---|---|---|
| Runtime | PHP 8.2+ FPM | Fibers + readonly classes + enum native |
| Web server | Nginx 1.24+ | Rate limit zones, gzip, HTTP/2 |
| Database (primary) | MySQL 8.0+ | `JSON` columns for settings/features; `GENERATED` columns for computed fields |
| Database (replica) | MySQL 8.0+ read replica | Phase 3+ |
| Cache / Queue | Redis 7.x | `predis/predis ^2` or `phpredis` ext |
| File storage | Cloudflare R2 (S3-compat) | Phase 3; zero egress cost |
| Auth | JWT (HS256-SHA512) + PHP Sessions | Dual guard — API + Web |
| Background jobs | Redis queue + Supervisor | `bin/worker.php` |
| Mobile client | Flutter (Phase 3) | Consumes `/api/v1/*` |
| Dependency injection | Custom PSR-11 container | `bootstrap/bindings.php` |
| Testing | PHPUnit 11+ | Unit (services) + Feature (full HTTP) + Tenant isolation |
| Static analysis | PHPStan level 8 | Enforces interface contracts |
| Code style | PHP-CS-Fixer PSR-12 | Git pre-commit hook |

---

## 13. CRM Module — Customer Pipeline, Campaigns & Schemes

> **Purpose:** Give every tenant a built-in micro-CRM that converts warranty service contacts into repeat buyers, enables targeted bulk marketing via email and WhatsApp, gives management real-time dealer sales visibility, and lets the parent company push time-bound promotional schemes directly to the dealer network.

---

### 13.1 CRM Data Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         CRM MODULE DATA FLOW                             │
│                                                                          │
│  Battery Handshake (HandshakeCaptured event)                             │
│        │                                                                 │
│        ▼                                                                 │
│  AutoEnrichCustomerOnHandshake listener                                  │
│        │  UPSERT crm_customers (phone as dedup key)                      │
│        │  Increment total_batteries_bought                               │
│        │  Set last_purchase_at = NOW()                                   │
│        ▼                                                                 │
│  crm_customers (TABLE 39)                                                │
│        │                                                                 │
│        ├──── crm_leads (TABLE 40) ◄──── Manual entry / campaign reply    │
│        │          │                                                      │
│        │          └──── crm_lead_activities (TABLE 41) — timeline        │
│        │                                                                 │
│        └──── crm_campaign_recipients (TABLE 45) ◄── SegmentService       │
│                       │                                                  │
│              crm_campaigns (TABLE 44)                                    │
│                   ├── crm_message_templates (TABLE 42)                   │
│                   ├── crm_segments (TABLE 43)                            │
│                   └── crm_schemes (TABLE 47) ← Parent-company offer      │
│                                                                          │
│  DealerSalesRollupJob (nightly) ──► crm_dealer_sales_daily (TABLE 49)   │
│                                          │                               │
│                           Sales graphs / leaderboard (§9.5)             │
└──────────────────────────────────────────────────────────────────────────┘
```

---

### 13.2 Customer Lifecycle Stages

| Stage | Meaning | Trigger |
|-------|---------|---------|
| `LEAD` | Phone/email captured but no purchase yet | Manual entry or campaign response |
| `PROSPECT` | Engaged (lead activity logged, demo given) | Manual stage upgrade via pipeline |
| `ACTIVE` | Has made at least one battery purchase | First `WON` lead (§5.18) |
| `REPEAT` | Two or more purchases | Second `WON` lead on same customer |
| `CHURNED` | No purchase in 180 days + no open lead | Weekly cron (`ChurnDetectionJob`) |

**ChurnDetectionJob (weekly, Sunday 02:00 IST):**
```sql
UPDATE crm_customers
   SET lifecycle_stage = 'CHURNED'
WHERE lifecycle_stage = 'ACTIVE'
  AND tenant_id = :tid
  AND last_purchase_at < NOW() - INTERVAL 180 DAY
  AND id NOT IN (
      SELECT customer_id FROM crm_leads
       WHERE stage NOT IN ('WON','LOST')
         AND tenant_id = :tid
  );
```

---

### 13.3 Dealer Dashboard — Sales Graph Widget

The dealer dashboard renders three charts from `crm_dealer_sales_daily`:

| Chart | Type | Data Series | Period |
|-------|------|-------------|--------|
| **Delivery Trend** | Line (batteries_delivered) | Daily deliveries + 7-day MA | Last 90 days |
| **Revenue vs Incentives** | Grouped Bar | incentives_paid overlay | Last 12 months |
| **Customer Acquisition** | Area | active_customers per day | Last 30 days |

**Front-end implementation (Vanilla JS ES2020):**
```javascript
// public/assets/js/crm-charts.js
// Uses Chart.js CDN (no build step — matches existing vanilla JS pattern)

async function renderDealerSalesGraph(dealerId, days = 90) {
  const res = await apiFetch(`/api/v1/crm/dealer-sales/${dealerId}/graph?days=${days}`);
  const { series } = await res.json();

  new Chart(document.getElementById('deliveryChart'), {
    type: 'line',
    data: {
      labels:   series.map(r => r.date),
      datasets: [{
        label: 'Batteries Delivered',
        data:  series.map(r => r.delivered),
        tension: 0.3, fill: true,
      }],
    },
    options: { responsive: true, plugins: { legend: { position: 'bottom' } } },
  });
}
```

---

### 13.4 Parent Company Scheme Integration

**Scheme creation flow:**

```
ADMIN/CRM_MGR (parent company)
    │
    ├── POST /api/v1/crm/schemes
    │     body: { name, type, discount_pct, valid_from, valid_to, target_role }
    │
    ├── POST /api/v1/crm/schemes/{id}/targets
    │     body: [{ dealer_id, volume_target, incentive_on_hit }, ...]
    │
    └── Dealer dashboard now shows scheme card:
          "Sell 50 units in April → earn ₹2,000 bonus"
          [Progress bar: 32/50 units ███████░░░ 64%]
          [14 days remaining]
```

**Scheme types and their marketing use:**

| Type | How it works | Dealer sees |
|------|-------------|-------------|
| `DISCOUNT` | % off listed price on new sales; scheme code on invoice | "Use code APR10 for 10% off" |
| `CASHBACK` | Fixed INR cashback credited per unit after handshake confirmation | "Earn ₹50 cashback per battery" |
| `VOLUME_INCENTIVE` | Bonus paid when dealer crosses `volume_target` in scheme window | "Sell 50 batteries → ₹2,000 bonus" |
| `COMBO_OFFER` | Multi-SKU bundle offer (stored as JSON in `terms_text`) | "Buy Type A + Type B → free tester kit" |
| `LOYALTY` | Tiered incentive based on cumulative `total_batteries_bought` (cross-scheme) | "Platinum dealer: 2× incentive rate" |

**Campaign + Scheme linking:**  
A campaign can attach `scheme_id` so that the offer details are auto-populated in templates via `{{scheme_name}}`, `{{offer_details}}`, `{{valid_until}}` variables — no manual copy-paste of offer text needed.

---

### 13.5 Bulk Email & WhatsApp Channel Configuration

**Email channel** (extends existing PHPMailer setup):

| Config Key | Description | Default |
|------------|-------------|---------|
| `MAIL_RATE_PER_MIN` | Max emails/min for campaign blasts | `200` |
| `MAIL_UNSUBSCRIBE_SECRET` | HMAC salt for unsubscribe token generation | — (required) |
| `CAMPAIGN_FROM_NAME` | Sender name override for campaigns | `APP_NAME` |
| `CAMPAIGN_FROM_EMAIL` | Dedicated campaign sending address | `MAIL_FROM` |

**WhatsApp channel (Phase 3 — BSP integration):**

> `WhatsAppChannel.php` in `app/Modules/Notifications/Channels/` already exists as a stub (§3).  
> CRM module activates it for campaign use via the same interface.

| Config Key | Description |
|------------|-------------|
| `WA_BSP_PROVIDER` | `twilio` \| `gupshup` \| `meta_cloud` |
| `WA_API_KEY` | BSP API key |
| `WA_PHONE_NUMBER_ID` | Registered BSP number ID |
| `WA_RATE_PER_MIN` | Max WA messages/min (BSP tier) — default `80` |
| `WA_TEMPLATE_NAMESPACE` | Pre-approved WA message template namespace |

**WhatsApp compliance rules (WABA policy):**
1. Only send to customers who have messaged the business account first (session window) — or use pre-approved BSP templates for outbound (`MARKETING` category)
2. `crm_opt_outs` enforced on every dispatch — WhatsApp BSP opt-out webhooks mapped to `crm_opt_outs` rows automatically
3. Message content rendered from `body_text` field of template only; no HTML
4. Frequency cap: max 2 marketing messages per customer per week enforced in `CampaignService::buildRecipientList()`

```php
// Frequency cap check (WhatsApp)
$recentCampaignCount = DB::selectOne("
    SELECT COUNT(DISTINCT r.campaign_id) AS cnt
    FROM crm_campaign_recipients r
    JOIN crm_campaigns c ON c.id = r.campaign_id
    WHERE r.customer_id = :cid
      AND r.channel = 'WHATSAPP'
      AND r.status IN ('SENT','DELIVERED','OPENED')
      AND c.dispatched_at >= NOW() - INTERVAL 7 DAY
", ['cid' => $customerId]);

if ($recentCampaignCount->cnt >= 2) {
    // Skip this customer for this campaign batch
    $recipient->update(['status' => 'OPTED_OUT', 'failure_reason' => 'frequency_cap']);
    continue;
}
```

---

### 13.6 Security Considerations — CRM Module

| Threat | Mitigation |
|--------|------------|
| **SQL injection via segment field names** | Field names from JSON rules are validated against `FIELD_WHITELIST` map before SQL construction (§5.20) — raw string interpolation never used |
| **Template injection / SSTI** | Message templates rendered via twig-sandbox with restricted allow-list; `eval()` / `extract()` forbidden; template stored as raw text, rendered at dispatch only |
| **Unsubscribe token forgery** | Token = SHA-256(recipient_id + campaign_id + `MAIL_UNSUBSCRIBE_SECRET`); stored hashed; single-use flag prevents replay |
| **Customer PII exposure (bulk export)** | `GET /api/v1/crm/customers` returns paginated rows only; no bulk CSV dump endpoint without explicit `reports.export` permission |
| **WhatsApp spam / unsolicited messages** | Opt-out table enforced; weekly frequency cap (≤2 campaigns/7 days) hard-coded in service; WABA pre-approved templates required for `MARKETING` category |
| **Campaign impersonation (IDOR)** | All campaign/customer/lead endpoints scope `WHERE tenant_id = JWT.tenant_id`; dealers further scoped to `WHERE dealer_id = JWT.user_id` |
| **Mass assignment on customer update** | `CustomerController::update()` accepts only allow-listed fields: `name`, `email`, `city`, `state`, `pincode`, `notes` |
| **Scheme backdating fraud** | `SchemeService::create()` enforces `valid_from >= TODAY`; targets cannot be altered once any campaign references the scheme |

---

### 13.7 CRM Phase Roadmap

| Phase | Item | What |
|-------|------|------|
| **Phase 2** | Customer auto-enrichment | `AutoEnrichCustomerOnHandshake` listener goes live with HandshakeCaptured event |
| **Phase 2** | Lead pipeline | Manual lead management, stage transitions, activity log |
| **Phase 2** | Dealer sales graph | `DealerSalesRollupJob` nightly + chart widget |
| **Phase 2** | Scheme management | Parent-company scheme CRUD + dealer target assignment |
| **Phase 3** | Email campaigns | Segment builder + template engine + PHPMailer dispatch + unsubscribe |
| **Phase 3** | WhatsApp campaigns | BSP integration (`WA_BSP_PROVIDER`) + frequency cap + opt-out webhook |
| **Phase 3** | Campaign analytics | Delivery funnel dashboard (§9.6) |
| **Phase 4** | Automated journeys | Time-based drip sequences (e.g., warranty expiry reminder 30 days before) |
| **Phase 4** | AI offer personalisation | ML scoring model ranks scheme relevance per customer based on purchase history |
| **Phase 4** | Referral tracking | `referral_code` on `crm_customers`; credit dealer when referred customer purchases |

---

## 14. Public Repair Status Tracking

> **Purpose:** Let customers and dealers check claim repair progress with a single click — no login required.  
> A unique tracking link is embedded in every claim confirmation and status-change email/WhatsApp message.  
> Customers can also enter their ticket number on a public lookup page to retrieve the same link.

---

### 14.1 Tracking Page Data Model

The JSON payload returned by `GET /api/v1/track/{token}` and used to render the HTML tracking page:

```json
{
  "claim_number": "ACME-CLM-2026-00001",
  "current_status": "AT_SERVICE",
  "current_status_label": "Battery at Service Centre",
  "current_status_description": "Our technicians are inspecting your battery.",
  "battery_serial_masked": "**********1234",
  "dealer_name": "Sunrise Auto Parts",
  "service_centre_name": "Central Battery Service Hub",
  "created_at": "2026-04-10T08:30:00+05:30",
  "last_updated_at": "2026-04-12T14:22:00+05:30",
  "timeline": [
    {
      "status": "SUBMITTED",
      "label": "Claim Submitted",
      "description": "Your claim has been received.",
      "occurred_at": "2026-04-10T08:30:00+05:30"
    },
    {
      "status": "DRIVER_RECEIVED",
      "label": "Picked Up by Driver",
      "description": "Our driver has collected the battery.",
      "occurred_at": "2026-04-11T10:05:00+05:30"
    },
    {
      "status": "AT_SERVICE",
      "label": "Battery at Service Centre",
      "description": "Our technicians are inspecting your battery.",
      "occurred_at": "2026-04-12T14:22:00+05:30"
    }
  ],
  "is_closed": false,
  "tracking_expires_at": "2026-07-10T08:30:00+05:30",
  "dealer_contact": {
    "name": "Sunrise Auto Parts",
    "city": "Mumbai"
  }
}
```

> **Note:** Customer phone, email, and full address are NEVER included. `battery_serial_masked` shows only the last 4 characters (`**********1234`) and is derived server-side. Dealer `city` only — no street address.

---

### 14.2 Claim Status Label Map

All 9 claim states mapped to customer-facing labels, icons, and descriptions for the tracking page:

| State | Customer Label | Icon | Customer-Facing Description |
|---|---|---|---|
| `DRAFT` | Claim Being Prepared | 📋 | Your dealer is preparing the claim details. |
| `SUBMITTED` | Claim Submitted | ✅ | Your claim has been received and is being reviewed. |
| `DRIVER_RECEIVED` | Picked Up by Driver | 🚗 | Our driver has collected the battery from your dealer. |
| `IN_TRANSIT` | Battery in Transit | 🚚 | Your battery is on its way to the service centre. |
| `AT_SERVICE` | Battery at Service Centre | 🔧 | Our technicians are inspecting your battery. |
| `DIAGNOSED` | Diagnosis Complete | 🔍 | We have completed the diagnosis. Your case is being processed. |
| `REPLACED` | Replacement Dispatched | 📦 | A replacement battery is on its way back to your dealer. |
| `READY_FOR_RETURN` | Ready for Pickup | 🎉 | Your repaired/replaced battery is ready. Contact your dealer to arrange pickup. |
| `CLOSED` | Service Complete | ✔️ | Your service request has been completed. Thank you. |

```php
// app/Modules/Tracking/Services/ClaimStatusLabels.php

class ClaimStatusLabels
{
    private const MAP = [
        'DRAFT'            => ['label' => 'Claim Being Prepared',      'icon' => '📋',
                               'desc'  => 'Your dealer is preparing the claim details.'],
        'SUBMITTED'        => ['label' => 'Claim Submitted',           'icon' => '✅',
                               'desc'  => 'Your claim has been received and is being reviewed.'],
        'DRIVER_RECEIVED'  => ['label' => 'Picked Up by Driver',       'icon' => '🚗',
                               'desc'  => 'Our driver has collected the battery from your dealer.'],
        'IN_TRANSIT'       => ['label' => 'Battery in Transit',        'icon' => '🚚',
                               'desc'  => 'Your battery is on its way to the service centre.'],
        'AT_SERVICE'       => ['label' => 'Battery at Service Centre', 'icon' => '🔧',
                               'desc'  => 'Our technicians are inspecting your battery.'],
        'DIAGNOSED'        => ['label' => 'Diagnosis Complete',        'icon' => '🔍',
                               'desc'  => 'We have completed the diagnosis. Your case is being processed.'],
        'REPLACED'         => ['label' => 'Replacement Dispatched',    'icon' => '📦',
                               'desc'  => 'A replacement battery is on its way back to your dealer.'],
        'READY_FOR_RETURN' => ['label' => 'Ready for Pickup',          'icon' => '🎉',
                               'desc'  => 'Your battery is ready. Contact your dealer to arrange pickup.'],
        'CLOSED'           => ['label' => 'Service Complete',          'icon' => '✔️',
                               'desc'  => 'Your service request has been completed. Thank you.'],
    ];

    public static function forCustomer(string $status): array
    {
        return self::MAP[$status] ?? ['label' => $status, 'icon' => '⏳', 'desc' => ''];
    }
}
```

---

### 14.3 Ticket Number Lookup Page

**URL:** `/track` (GET) — renders a simple HTML form  
**Action:** `POST /track/lookup` — resolves ticket number to tracking token

**UI flow:**

```
┌─────────────────────────────────────────────────────────┐
│  🔍  Track Your Battery Service                         │
│                                                         │
│  Enter your ticket / claim number:                      │
│  ┌─────────────────────────────────────────────────┐    │
│  │  ACME-CLM-2026-00001                            │    │
│  └─────────────────────────────────────────────────┘    │
│                                                         │
│  [ Track Now → ]                                        │
│                                                         │
│  Tip: Your ticket number is in the confirmation         │
│  email or WhatsApp message you received.                │
└─────────────────────────────────────────────────────────┘
```

**Error states shown on the same page (no redirect on error):**

| Condition | Message shown |
|---|---|
| Ticket not found | "We could not find a claim with that ticket number. Please check and try again." |
| Token expired | "The tracking link for this ticket has expired. Please contact your dealer." |
| Rate-limited (429) | "Too many attempts. Please wait a few minutes and try again." |
| Invalid format | "Please enter a valid ticket number (e.g. ACME-CLM-2026-00001)." |

**Rate-limit implementation (TABLE 52):**

```php
// Max 10 lookup attempts per IP per 15-minute window
$count = DB::queryOne(
    'SELECT COUNT(*) AS n FROM ticket_lookup_attempts
      WHERE ip_address = ? AND attempted_at > NOW() - INTERVAL 15 MINUTE',
    [$_SERVER['REMOTE_ADDR']]
)['n'];

if ($count >= 10) {
    http_response_code(429);
    return ['error' => 'Too many attempts. Please wait a few minutes.'];
}
```

---

### 14.4 Email & WhatsApp Tracking URL Injection

**Email template snippet** (injected into every claim email body — TABLE 20):

```html
<!-- Tracking link block — appended above email footer -->
<div style="margin:24px 0; text-align:center;">
  <a href="{{tracking_url}}"
     style="background:#1a73e8; color:#fff; padding:12px 28px;
            border-radius:6px; text-decoration:none; font-size:15px;">
    🔍 Track Repair Progress
  </a>
  <p style="font-size:12px; color:#666; margin-top:8px;">
    No login required. This link is valid for 90 days.
  </p>
</div>
```

**WhatsApp message template** (pre-approved UTILITY category — no login required):

```
*Battery Service Update* 🔧

Hi {{customer_name}},

Your claim *{{claim_number}}* status has been updated to:
*{{status_label}}* — {{status_description}}

Track your repair progress anytime (no login needed):
{{tracking_url}}

Dealer: {{dealer_name}}
— {{tenant_name}} Support Team
```

> **Template category:** `UTILITY` (not MARKETING) — auto-approved by WhatsApp / BSP.  
> Template name convention: `repair_status_update_v1` — register in BSP dashboard before go-live.

**Events that trigger the notification + URL injection:**

| Event | Trigger | Email | WhatsApp |
|---|---|---|---|
| `ClaimCreated` | Claim created by dealer | ✅ Welcome + tracking link | ✅ (Phase 3) |
| `ClaimStatusChanged` | Any state transition | ✅ Status update + tracking link | ✅ (Phase 3) |
| `DiagnosisCompleted` | Diagnosis notes added | ✅ Diagnosis summary | ✅ (Phase 3) |
| `ReplacementAssigned` | Replacement battery assigned | ✅ Replacement dispatched | ✅ (Phase 3) |

---

### 14.5 WhatsApp Bot Flow (Phase 3/4)

**Keyword trigger:** Customer sends any of `STATUS`, `TRACK`, `REPAIR`, or pastes their ticket number to the BSP-registered number.

```
Incoming WhatsApp message from customer
          ↓
WhatsApp Webhook POST /api/v1/webhooks/whatsapp
          ↓
WhatsAppBotController::handle()
  1. Extract sender phone number from payload
  2. Normalize message body → uppercase; strip whitespace
  3. If body matches /^[A-Z0-9]+-CLM-\d{4}-\d{5}$/ → treat as ticket number
     Else if body IN ('STATUS', 'TRACK', 'REPAIR') → prompt for ticket number:
       Reply: "Please reply with your claim ticket number
               (e.g. ACME-CLM-2026-00001) to track your repair."
  4. Look up claim by ticket number (tenant-scoped by inbound phone number → tenant)
     If not found → Reply: "We couldn't find that claim number.
                            Please check the ticket in your confirmation email."
  5. Build status reply using ClaimStatusLabels::forCustomer()
  6. Append tracking URL from TrackingService::getOrCreateToken()
  7. Send reply via WhatsAppChannel::send()
```

**WhatsApp bot reply format:**

```
Your repair status for *ACME-CLM-2026-00001*:

🔧 *Battery at Service Centre*
Our technicians are inspecting your battery.

📅 Last updated: 12 Apr 2026, 2:22 PM

🔗 Full tracking page (no login needed):
https://track.yourdomain.com/track/3fa2c84d...

Reply STATUS anytime to check your repair progress.
```

**Rate-limit:** WhatsApp bot replies are debounced — no more than 1 automated reply per phone number per 5 minutes (Redis TTL key: `wa:bot:ratelimit:{phone}`).

---

### 14.6 Security Considerations

| Risk | Mitigation |
|---|---|
| **Token enumeration** | 256-bit random token (64-char hex) — brute-force requires 2²⁵⁶ attempts; infeasible |
| **Claim number enumeration via lookup** | TABLE 52 rate-limit: max 10 attempts / IP / 15 min; generic error messages never confirm claim existence |
| **Cross-tenant data leak** | Lookup always scopes `WHERE tenant_id = TenantContext::id()`; token resolution does not — but token is cryptographically bound to a single claim which carries a `tenant_id` |
| **PII exposure on tracking page** | Only show: claim number, status, battery serial (last 4 chars masked), dealer name, dealer city. Never expose: customer phone, email, address, full battery serial, or replacement battery serial |
| **Token forwarding / unauthorized sharing** | By design, the URL is shareable (ticket-based access). Customers are informed: "Anyone with this link can view your repair status." |
| **Expired token misuse** | `expires_at` checked on every request; expired tokens return a safe "link expired" message — no data returned |
| **HTTPS enforcement** | `Strict-Transport-Security: max-age=31536000; includeSubDomains` header; HTTP requests redirected 301 to HTTPS; tracking links generated with `https://` scheme only |
| **WhatsApp webhook spoofing** | BSP webhook signature verified via HMAC-SHA256 (`X-Hub-Signature-256` header) before any processing |
| **Token in server logs** | Access logs should be configured to NOT log full `/track/{token}` path — mask with `/track/[REDACTED]` in Nginx log format |

**Nginx log masking example:**

```nginx
# In nginx.conf — mask tracking tokens from access log
map $uri $masked_uri {
    ~^/track/([a-f0-9]{64})$ /track/[REDACTED];
    default                   $uri;
}
log_format masked_main '$remote_addr - $remote_user [$time_local] '
    '"$request_method $masked_uri $server_protocol" '
    '$status $body_bytes_sent "$http_referer" "$http_user_agent"';
access_log /var/log/nginx/access.log masked_main;
```

---

### 14.7 Tracking Module Folder Structure

```
app/Modules/Tracking/
├── Controllers/
│   └── TrackingController.php
│       ├── resolve(string $token): Response     ← GET /track/{token} + /api/v1/track/{token}
│       ├── lookup(Request $req): Response        ← POST /track/lookup
│       └── page(): Response                      ← GET /track  (lookup form)
├── Services/
│   └── TrackingService.php
│       ├── issue(Claim $claim): string           ← Generate + store token; return URL
│       ├── getOrCreateToken(int $claimId): string ← Idempotent
│       ├── resolve(string $token): ?array        ← Resolve token → masked payload
│       └── maskPayload(array $row): array        ← Apply PII masking rules (§14.6)
├── Repositories/
│   └── TrackingRepository.php
│       ├── findByToken(string $token): ?array
│       ├── findByClaimId(int $claimId): ?array
│       ├── upsert(array $data): void
│       └── incrementViewCount(string $token): void
└── Routes/
    └── public.php                                ← No auth middleware
```

---

### 14.8 Tracking Phase Roadmap

| Phase | Feature | Notes |
|---|---|---|
| **Phase 2** | Token issuance on claim creation | `TrackingService::issue()` called from `ClaimService::create()` |
| **Phase 2** | HTML tracking page | Vanilla JS; progressive enhancement; no framework dependency |
| **Phase 2** | Token injection in emails | `NotifyOnClaimChange` updated (§5.22) |
| **Phase 2** | Ticket number lookup + rate limiting | TABLE 52; 10/IP/15min cap |
| **Phase 3** | WhatsApp tracking link in status updates | Feature-flagged: `features.whatsapp_tracking_alerts` |
| **Phase 3** | WhatsApp bot (keyword + ticket number) | BSP webhook; HMAC verification |
| **Phase 3** | Repair status push notifications (PWA) | Web Push API; token stored in `push_subscriptions` |
| **Phase 4** | Estimated completion date | ML-based ETA from historical service time |
| **Phase 4** | Customer feedback on claim closure | 1-click thumbs-up/down on CLOSED status page; stored in `claim_feedback` |

---

*Document Version: 4.1 · April 2026 · 52 Tables · 22 Business Logic Sections · 31 Security Controls · 22 Risk Items · SaaS + CRM + Public Repair Tracking*