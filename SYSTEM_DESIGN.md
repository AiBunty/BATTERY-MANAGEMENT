# SYSTEM_DESIGN.md
# Battery Service & Warranty Management System
**Stack:** PHP 8.2+ · MySQL 8.0+ · Redis · Vanilla JS (ES2020) / PWA · Google Maps API  
**Architecture:** Modular Monolith — API-first, Multi-tenant, SaaS-ready  
**Date:** April 2026  
**Version:** 3.0

---

## Table of Contents
1. [System Overview](#1-system-overview)
2. [Role Matrix](#2-role-matrix)
3. [Folder Structure](#3-folder-structure) — Modular Monolith
4. [Database Schema (SQL)](#4-database-schema-sql) — 30 Tables (incl. SaaS layer)
5. [Core Business Logic](#5-core-business-logic) — 14 Sections
6. [API Route Map](#6-api-route-map) — Versioned `/api/v1/`
7. [JS: Client-Side Image Compression](#7-js-client-side-image-compression)
8. [Security Architecture](#8-security-architecture)
9. [Analytics & Reporting](#9-analytics--reporting)
10. [Deployment Notes](#10-deployment-notes)
11. [Deep Risk Register](#11-deep-risk-register--additional-vulnerabilities-found) — 15 Items
12. [SaaS Architecture & Upgrade Roadmap](#12-saas-architecture--upgrade-roadmap)

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
│           Reports · Audit                                                  │
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

| Permission | ADMIN | SUPER_MGR | DISPATCH_MGR | DEALER | DRIVER | TESTER | INV_MGR |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Tally Import/Export | ✓ | ✓ | | | | | |
| Manage Users | ✓ | ✓ | | | | | |
| Settings | ✓ | | | | | | |
| Create Claim | | | | ✓ | | | |
| Edit Claim (pre-lock) | | | | ✓ | | | |
| View Claims | ✓ | ✓ | ✓ | Own | Assigned | | ✓ |
| Assign Driver Route | | | ✓ | | | | |
| Driver Mobile UI | | | | | ✓ | | |
| Inward Battery | | | | | | ✓* | ✓ |
| Diagnose Battery | | | | | | ✓ | |
| Assign Replacement | | | | | | | ✓ |
| Run Reports | ✓ | ✓ | ✓ | | | | |
| Finance Report | ✓ | ✓ | | | | | |

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
-- ============================================================
CREATE TABLE users (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name          VARCHAR(255)  NOT NULL,
    email         VARCHAR(255)  NOT NULL UNIQUE,
    phone         VARCHAR(20)   NULL,
    role          ENUM(
                    'ADMIN','DEALER','DRIVER','TESTER',
                    'INV_MANAGER','DISPATCH_MANAGER','SUPER_MANAGER'
                  ) NOT NULL,
    is_active     TINYINT(1)    NOT NULL DEFAULT 1,
    created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                          ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_role    (role),
    INDEX idx_active  (is_active)
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
-- ============================================================
CREATE TABLE batteries (
    id                INT UNSIGNED   AUTO_INCREMENT PRIMARY KEY,
    serial_number     VARCHAR(15)    NOT NULL UNIQUE,    -- 14-15 chars, A-Z0-9
    is_in_tally       TINYINT(1)     NOT NULL DEFAULT 0, -- Populated on Tally import
    mfg_year          SMALLINT UNSIGNED NULL,            -- Decoded from serial
    mfg_week          TINYINT UNSIGNED  NULL,            -- Decoded from serial (1-53)
    model             VARCHAR(100)   NULL,
    status            ENUM(
                        'IN_STOCK','CLAIMED','IN_TRANSIT',
                        'AT_SERVICE','REPLACED','SCRAPPED'
                      ) NOT NULL DEFAULT 'IN_STOCK',
    mother_battery_id INT UNSIGNED   NULL,               -- Linked-list: IMMEDIATE parent only (not root). Use recursive CTE (§5.4) to reach root.
    created_at        TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                               ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (mother_battery_id) REFERENCES batteries(id) ON DELETE SET NULL,
    INDEX idx_status      (status),
    INDEX idx_mother      (mother_battery_id),
    INDEX idx_mfg         (mfg_year, mfg_week)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 5: tally_imports
-- ============================================================
CREATE TABLE tally_imports (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    filename      VARCHAR(255)     NOT NULL,
    imported_by   INT UNSIGNED     NOT NULL,
    total_rows    INT UNSIGNED     NOT NULL DEFAULT 0,
    valid_rows    INT UNSIGNED     NOT NULL DEFAULT 0,
    invalid_rows  INT UNSIGNED     NOT NULL DEFAULT 0,
    inserted_rows INT UNSIGNED     NOT NULL DEFAULT 0,  -- new serials added
    upserted_rows INT UNSIGNED     NOT NULL DEFAULT 0,  -- existing serials refreshed (not CLAIMED)
    skipped_rows  INT UNSIGNED     NOT NULL DEFAULT 0,  -- CLAIMED/AT_SERVICE batteries left untouched
    imported_at   TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (imported_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 6: claims
-- ============================================================
CREATE TABLE claims (
    id                 INT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    claim_number       VARCHAR(20)   NOT NULL UNIQUE,       -- e.g. CLM-2026-00001
    battery_id         INT UNSIGNED  NOT NULL,
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
    FOREIGN KEY (battery_id) REFERENCES batteries(id),
    FOREIGN KEY (dealer_id)  REFERENCES users(id),
    INDEX idx_dealer        (dealer_id),
    INDEX idx_status        (status),
    INDEX idx_battery       (battery_id),
    INDEX idx_dealer_status (dealer_id, status)  -- composite: Dealer “My Claims” dashboard
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 7: driver_routes
-- ============================================================
CREATE TABLE driver_routes (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    driver_id    INT UNSIGNED NOT NULL,
    route_date   DATE         NOT NULL,
    status       ENUM('PLANNED','ACTIVE','COMPLETED') NOT NULL DEFAULT 'PLANNED',
    created_by   INT UNSIGNED NOT NULL,
    created_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (driver_id)  REFERENCES users(id),
    FOREIGN KEY (created_by) REFERENCES users(id),
    UNIQUE KEY uq_driver_date (driver_id, route_date),
    INDEX idx_date (route_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 8: driver_tasks
-- ============================================================
CREATE TABLE driver_tasks (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    route_id         INT UNSIGNED NOT NULL,
    claim_id         INT UNSIGNED NOT NULL,
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
    FOREIGN KEY (route_id) REFERENCES driver_routes(id) ON DELETE CASCADE,
    FOREIGN KEY (claim_id) REFERENCES claims(id),
    INDEX idx_route        (route_id),
    INDEX idx_claim        (claim_id),
    INDEX idx_status       (status),
    INDEX idx_route_status (route_id, status)          -- composite: Driver “Today’s Tasks” view
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 9: driver_stock
-- ============================================================
-- Records every battery movement for the nightly audit equation:
-- Morning Load + Pickups - Deliveries = End-of-Day Physical
CREATE TABLE driver_stock (
    id            INT UNSIGNED   AUTO_INCREMENT PRIMARY KEY,
    driver_id     INT UNSIGNED   NOT NULL,
    stock_date    DATE           NOT NULL,
    battery_id    INT UNSIGNED   NOT NULL,
    action        ENUM(
                    'MORNING_LOAD',  -- Batteries loaded at start of day
                    'DELIVERED',     -- Battery given to dealer
                    'PICKED_UP',     -- Faulty battery collected from dealer
                    'INWARD'         -- Battery handed to service centre
                  ) NOT NULL,
    task_id       INT UNSIGNED   NULL,       -- FK to driver_tasks if applicable
    created_at    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (driver_id)  REFERENCES users(id),
    FOREIGN KEY (battery_id) REFERENCES batteries(id),
    FOREIGN KEY (task_id)    REFERENCES driver_tasks(id) ON DELETE SET NULL,
    INDEX idx_driver_date (driver_id, stock_date),
    INDEX idx_battery     (battery_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 10: driver_handshakes
-- ============================================================
CREATE TABLE driver_handshakes (
    id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    route_id          INT UNSIGNED NOT NULL,
    dealer_id         INT UNSIGNED NOT NULL,
    batch_photo       VARCHAR(500) NOT NULL,   -- Photo of all units together
    dealer_signature  VARCHAR(500) NOT NULL,   -- Canvas PNG path
    handshake_at      TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (route_id)  REFERENCES driver_routes(id),
    FOREIGN KEY (dealer_id) REFERENCES users(id),
    INDEX idx_route (route_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 11: service_jobs
-- ============================================================
CREATE TABLE service_jobs (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    claim_id        INT UNSIGNED NOT NULL,
    inward_by       INT UNSIGNED NOT NULL,
    inward_at       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    assigned_tester INT UNSIGNED NULL,
    diagnosis       ENUM('PENDING','OK','REPLACE') NOT NULL DEFAULT 'PENDING',
    diagnosis_notes TEXT         NULL,
    diagnosed_at    TIMESTAMP    NULL,
    FOREIGN KEY (claim_id)        REFERENCES claims(id),
    FOREIGN KEY (inward_by)       REFERENCES users(id),
    FOREIGN KEY (assigned_tester) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_claim     (claim_id),
    INDEX idx_diagnosis (diagnosis)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 12: replacements
-- ============================================================
CREATE TABLE replacements (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    service_job_id  INT UNSIGNED NOT NULL,
    old_battery_id  INT UNSIGNED NOT NULL,
    new_battery_id  INT UNSIGNED NOT NULL,
    assigned_by     INT UNSIGNED NOT NULL,
    replaced_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (service_job_id) REFERENCES service_jobs(id),
    FOREIGN KEY (old_battery_id) REFERENCES batteries(id),
    FOREIGN KEY (new_battery_id) REFERENCES batteries(id),
    FOREIGN KEY (assigned_by)    REFERENCES users(id),
    UNIQUE KEY uq_new_battery (new_battery_id)    -- One replacement serial used once
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 13: delivery_incentives
-- ============================================================
CREATE TABLE delivery_incentives (
    id            INT UNSIGNED   AUTO_INCREMENT PRIMARY KEY,
    driver_id     INT UNSIGNED   NOT NULL,
    task_id       INT UNSIGNED   NOT NULL UNIQUE,
    claim_id      INT UNSIGNED   NOT NULL,
    handshake_id  INT UNSIGNED   NOT NULL,             -- REQUIRED: incentive is forbidden without a physical handshake
    task_type     ENUM('DELIVERY_NEW','DELIVERY_REPLACEMENT') NOT NULL,  -- both task types earn incentive
    amount        DECIMAL(10,2)  NOT NULL,             -- copied from settings at time of delivery
    delivery_date DATE           NOT NULL,
    is_paid       TINYINT(1)     NOT NULL DEFAULT 0,
    paid_at       TIMESTAMP      NULL,
    FOREIGN KEY (driver_id)    REFERENCES users(id),
    FOREIGN KEY (task_id)      REFERENCES driver_tasks(id),
    FOREIGN KEY (claim_id)     REFERENCES claims(id),
    FOREIGN KEY (handshake_id) REFERENCES driver_handshakes(id),
    INDEX idx_driver_month   (driver_id, delivery_date),
    INDEX idx_paid           (is_paid),
    INDEX idx_incentive_paid (driver_id, is_paid, delivery_date)   -- composite: monthly payout report
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
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_entity   (entity_type, entity_id),
    INDEX idx_user     (user_id),
    INDEX idx_created  (created_at),
    INDEX idx_severity (severity)            -- Admins can filter HIGH/CRITICAL fraud alerts directly
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
    claim_id    INT UNSIGNED     NOT NULL,
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
-- Tracks OTP verification attempts for rate-limiting (§5.9).
-- 5 failures in a 10-minute window → AuthException thrown + CRITICAL audit log.
CREATE TABLE login_attempts (
    id           INT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    user_id      INT UNSIGNED  NOT NULL,
    attempted_at TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ip_address   VARCHAR(45)   NOT NULL,
    success      TINYINT(1)    NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_window (user_id, attempted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 20: email_queue
-- ============================================================
-- OTP emails are NEVER sent synchronously during an HTTP request.
-- bin/process-email-queue.php (cron every minute) drains this table.
CREATE TABLE email_queue (
    id           INT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    recipient    VARCHAR(255)  NOT NULL,
    subject      VARCHAR(255)  NOT NULL,
    body         TEXT          NOT NULL,
    status       ENUM('PENDING','SENT','FAILED') NOT NULL DEFAULT 'PENDING',
    attempts     TINYINT       NOT NULL DEFAULT 0,   -- max 3 before FAILED
    last_attempt TIMESTAMP     NULL,
    sent_at      TIMESTAMP     NULL,
    created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_pending (status, attempts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- TABLE 21: driver_eod_audits
-- ============================================================
-- Persists each driver's nightly stock verification for historical reporting.
-- Corrected equation: expected_eod = morning_load + picked_up - delivered - inwarded (§5.5)
CREATE TABLE driver_eod_audits (
    id            INT UNSIGNED       AUTO_INCREMENT PRIMARY KEY,
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
    FOREIGN KEY (driver_id) REFERENCES users(id),
    UNIQUE KEY uq_driver_date (driver_id, audit_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### SaaS Tables (Phase 1 additions — TABLE 22–30)

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
    id            BIGINT UNSIGNED  AUTO_INCREMENT PRIMARY KEY,
    tenant_id     BIGINT UNSIGNED  NOT NULL,
    uploaded_by   INT UNSIGNED     NOT NULL,
    entity_type   VARCHAR(60)      NOT NULL,                 -- "claim", "handshake", "tally"
    entity_id     BIGINT UNSIGNED  NOT NULL,
    storage_driver VARCHAR(20)     NOT NULL DEFAULT 'local',  -- 'local', 's3', 'r2'
    disk_path     VARCHAR(512)     NOT NULL,                  -- relative key on that driver
    mime_type     VARCHAR(100)     NOT NULL,
    file_size_kb  INT UNSIGNED     NOT NULL DEFAULT 0,
    original_name VARCHAR(255)     NOT NULL,
    is_deleted    TINYINT(1)       NOT NULL DEFAULT 0,        -- soft-delete; physical purge by cron
    created_at    TIMESTAMP        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (tenant_id)   REFERENCES tenants(id),
    FOREIGN KEY (uploaded_by) REFERENCES users(id),
    INDEX idx_entity (tenant_id, entity_type, entity_id)
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
| 7 | `driver_stock` | `(tenant_id, driver_id, audit_date)` |
| 8 | `driver_handshakes` | `(tenant_id, driver_id, created_at)` |
| 9 | `service_jobs` | `(tenant_id, status)` |
| 10 | `replacements` | `(tenant_id, claim_id)` |
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
-- Given ANY serial in a replacement chain, return full history
WITH RECURSIVE lineage AS (
    -- Anchor: find the ultimate mother (no mother_battery_id)
    SELECT b.id, b.serial_number, b.mother_battery_id,
           b.status, b.mfg_year, b.mfg_week, 0 AS generation
    FROM   batteries b
    WHERE  b.id = :start_id

    UNION ALL

    -- Recurse UP to find root
    SELECT p.id, p.serial_number, p.mother_battery_id,
           p.status, p.mfg_year, p.mfg_week, l.generation - 1
    FROM   batteries p
    JOIN   lineage   l ON p.id = l.mother_battery_id
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

### 5.8 Claim Number Generation (Race-Free)

```php
// ClaimService::generateClaimNumber(): string
// SELECT … FOR UPDATE on claim_sequences prevents duplicate numbers under concurrent load.

public function generateClaimNumber(): string {
    $prefix = 'CLM-' . date('Y') . '-';
    $this->db->beginTransaction();
    try {
        $row = $this->db->query(
            "SELECT last_val FROM claim_sequences WHERE prefix = ? FOR UPDATE",
            [$prefix]
        )->fetch();

        if (!$row) {
            $this->db->exec(
                "INSERT INTO claim_sequences (prefix, last_val) VALUES (?, 0)", [$prefix]
            );
            $next = 1;
        } else {
            $next = $row['last_val'] + 1;
        }

        $this->db->exec(
            "UPDATE claim_sequences SET last_val = ? WHERE prefix = ?",
            [$next, $prefix]
        );
        $this->db->commit();
        return $prefix . str_pad($next, 5, '0', STR_PAD_LEFT);
    } catch (\Throwable $e) {
        $this->db->rollBack();
        throw $e;
    }
}
```

---

### 5.9 OTP Rate Limiting

```php
// AuthService::checkRateLimit(int $userId, string $ip): void
// Called at the START of AuthController::verifyOtp(), before any token lookup.

public function checkRateLimit(int $userId, string $ip): void {
    $window = date('Y-m-d H:i:s', strtotime('-10 minutes'));
    $count  = (int) $this->db->query(
        "SELECT COUNT(*) FROM login_attempts
         WHERE user_id = ? AND success = 0 AND attempted_at > ?",
        [$userId, $window]
    )->fetchColumn();

    if ($count >= 5) {
        $this->db->exec(
            "INSERT INTO audit_logs
             (user_id, action, entity_type, entity_id, ip_address, severity)
             VALUES (?, 'otp.rate_limited', 'users', ?, ?, 'CRITICAL')",
            [$userId, $userId, $ip]
        );
        throw new AuthException('Too many failed attempts. Retry in 10 minutes.');
    }
}

// Verification flow in AuthController::verifyOtp():
//   1. checkRateLimit($user->id, $_SERVER['REMOTE_ADDR'])
//   2. SELECT token_hash, expires_at, used FROM otp_tokens
//      WHERE user_id=? AND used=0 AND expires_at > NOW()
//      ORDER BY created_at DESC LIMIT 1
//   3. if (!hash_equals(hash('sha256', $inputOtp), $row['token_hash'])) {
//          INSERT login_attempts (user_id, ip_address, success=0)
//          throw AuthException('Invalid OTP')
//      }
//   4. On success: UPDATE otp_tokens SET used=1; INSERT login_attempts (success=1)
//   5. session_regenerate_id(true); create session
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

Every inbound request resolves a tenant **before** controllers execute. All repository queries
automatically inject the tenant context so cross-tenant data leaks are structurally impossible.

```php
// app/Shared/Auth/Middleware/TenantMiddleware.php
class TenantMiddleware {
    public function handle(Request $request, callable $next): Response {
        // 1. Try subdomain: acme.battery-mgmt.com → slug = 'acme'
        $slug = $this->extractSubdomain($request->host());

        // 2. Fallback: X-Tenant-ID header (for mobile / API clients on bare domain)
        if (!$slug) {
            $slug = $request->header('X-Tenant-ID');
        }

        // 3. JWT claim: tenant_id embedded at token issuance
        if (!$slug && $jwtTenantId = $this->jwtService->getTenantId($request)) {
            TenantContext::setById($jwtTenantId);
        } else {
            $tenant = $this->tenantRepo->findBySlug($slug)
                ?? throw new TenantException("Unknown tenant: {$slug}", 404);

            if (!$tenant->is_active) {
                throw new TenantException("Tenant suspended", 403);
            }
            TenantContext::set($tenant);
        }

        return $next($request);
    }
}

// app/Shared/Auth/TenantContext.php
class TenantContext {
    private static ?Tenant $current = null;

    public static function set(Tenant $tenant): void   { self::$current = $tenant; }
    public static function current(): Tenant           { return self::$current ?? throw new TenantException('No tenant context'); }
    public static function id(): int                   { return self::current()->id; }
    public static function clear(): void               { self::$current = null; }  // call in tests
}

// app/Shared/Database/QueryBuilder.php — automatic tenant scope
class QueryBuilder {
    public function forTenant(): static {
        return $this->where('tenant_id', TenantContext::id());
    }
}

// Usage in any repository:
// ClaimRepository::findAll() always calls ->forTenant() internally
// → controller is tenant-unaware; isolation is column-level, enforced in the query layer
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
```

### Queue Workers (Supervisor — when `QUEUE_DRIVER=redis`)

```ini
; /etc/supervisor/conf.d/battery-worker.conf
[program:battery-worker]
command=php /var/www/bin/worker.php --queues=emails,reports,tally
numprocs=2
autostart=true
autorestart=true
stdout_logfile=/var/log/battery-worker.log
```

```bash
# Manual start (development)
php bin/worker.php --queues=emails,reports,tally --sleep=1 --max-jobs=500
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
    NotifyOnClaimChange::class,       // always
    AuditClaimChanges::class,         // always
    TriggerIncentiveOnHandshake::class, // only if transition = DELIVERED
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
Refresh token: Opaque 64-byte random · 30-day TTL · stored as SHA-256 hash in `sessions` table
               Single-use: each refresh call rotates the refresh token (old hash invalidated)
```

**Token issuance flow:**

```
POST /api/v1/auth/verify-otp
  → AuthService::verifyOtp($email, $otp)
  → CleanUp login_attempts
  → JwtService::issue($user, $tenant)
     → accessToken  (signed JWT, 15 min)
     → refreshToken (random_bytes(64), stored hashed)
  → Response: { access_token, refresh_token, expires_in: 900 }
```

**Refresh flow:**

```
POST /api/v1/auth/refresh
  body: { refresh_token: "..." }
  → Hash incoming token with SHA-256
  → SELECT session WHERE token_hash = ? AND expires_at > now() AND is_revoked = 0
  → UPDATE session: revoke old row, insert new row (rotation)
  → JwtService::issue() → new access + refresh pair
```

**Rejection rules enforced in `ApiAuthMiddleware`:**

- `alg: none` → reject immediately  
- Expired `exp` → 401 (client must refresh)  
- Missing `tenant_id` claim → 401  
- `jti` in revocation list (Redis `SET jwt:revoked:{jti}` with TTL = remaining exp) → 401

---

### 12.6 Upgrade Roadmap

#### Phase 1 — SaaS Foundation *(Build with the system from Day 1)*

| Item | What |
|------|------|
| Multi-tenancy DB | `tenants`, `plans`, `tenant_settings`, `tenant_sequences` tables; `tenant_id` on all 18 operational tables |
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
| Request IDs | `X-Request-ID` header on every response; logged in `audit_logs.request_id` |
| Report snapshots | Async `GenerateReportJob` → write to `files` table; expire old snapshots |
| Feature flags | `tenant_settings` key `feature.{name}` → FeatureFlagService |
| Observability | Structured JSON logs → stdout; ERROR events fire `audit_logs CRITICAL`; health endpoints `/api/v1/health/live` + `/api/v1/health/ready` |

#### Phase 3 — Mobile & Scale *(6–12 months)*

| Item | What |
|------|------|
| Mobile API hardening | Flutter / React Native clients using `/api/v1/*`; push notification channel (FCM) added to `Notifications` module |
| S3 / R2 storage | Flip `STORAGE_DRIVER=r2` in `.env`; existing `files` rows retain `storage_driver=local` pointer |
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

*Document Version: 3.0 · May 2026 · 30 Tables · 14 Business Logic Sections · 22 Security Controls · 15 Risk Items · SaaS Architecture*

---

