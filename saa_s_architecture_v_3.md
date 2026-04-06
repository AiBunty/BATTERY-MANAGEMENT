# SaaS Architecture v3.1 — Redline Patch (QA Approved)

This document contains **exact corrections and improvements** required to upgrade v3 to **v3.1 production-ready SaaS architecture**.

---

# 🔴 CRITICAL FIXES (MUST IMPLEMENT)

## 1. Auth System Correction (Single Source of Truth)

### ❌ REMOVE (Incorrect / Conflicting)
- Any reference to refresh tokens stored in `sessions` table
- Any logic using `sessions.token_hash` for API refresh

### ✅ FINAL DESIGN

#### Table: `auth_refresh_tokens`
```sql
CREATE TABLE auth_refresh_tokens (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    tenant_id BIGINT UNSIGNED NOT NULL,
    user_id BIGINT UNSIGNED NOT NULL,
    token_hash CHAR(64) NOT NULL,
    device_id VARCHAR(128),
    device_name VARCHAR(255),
    ip_address VARCHAR(45) NOT NULL,
    user_agent VARCHAR(500),
    expires_at TIMESTAMP NOT NULL,
    revoked_at TIMESTAMP NULL,
    last_used_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_token_hash (token_hash),
    INDEX idx_user_active (tenant_id, user_id, revoked_at, expires_at)
);
```

### 🔒 RULES
- Rotate refresh token on every refresh
- Revoke old token atomically
- Reject reused token → possible breach

---

## 2. Foreign Key Type Alignment (CRITICAL DB BUG FIX)

### ❌ ISSUE
Mixed usage of:
- `INT UNSIGNED`
- `BIGINT UNSIGNED`

### ✅ RULE
All PK + FK must match EXACTLY

### 🔧 FIX TABLE-BY-TABLE

#### batteries
```sql
id BIGINT UNSIGNED PRIMARY KEY
```

#### claims
```sql
id BIGINT UNSIGNED
battery_id BIGINT UNSIGNED
created_by BIGINT UNSIGNED
```

#### service_jobs
```sql
id BIGINT UNSIGNED
claim_id BIGINT UNSIGNED
battery_id BIGINT UNSIGNED
assigned_to BIGINT UNSIGNED
```

#### driver_tasks
```sql
id BIGINT UNSIGNED
claim_id BIGINT UNSIGNED
assigned_to BIGINT UNSIGNED
```

#### driver_handshakes
```sql
id BIGINT UNSIGNED
driver_id BIGINT UNSIGNED
route_id BIGINT UNSIGNED
dealer_id BIGINT UNSIGNED
```

👉 Apply same for ALL referencing tables

---

## 3. FULL TENANT ENFORCEMENT (AUTHORITATIVE SCHEMA ONLY)

### ❌ REMOVE
- All "ALTER TABLE add tenant_id" sections from main schema

### ✅ FINAL RULE
Every operational table MUST include:

```sql
tenant_id BIGINT UNSIGNED NOT NULL
```

### 🔧 APPLY TO ALL TABLES

#### Already fixed (verify):
- users
- batteries
- claims
- files

#### MUST FIX (ADD tenant_id explicitly in schema):

```sql
-- driver
ALTER TABLE driver_routes ADD tenant_id BIGINT UNSIGNED NOT NULL;
ALTER TABLE driver_tasks ADD tenant_id BIGINT UNSIGNED NOT NULL;
ALTER TABLE driver_stock ADD tenant_id BIGINT UNSIGNED NOT NULL;
ALTER TABLE driver_handshakes ADD tenant_id BIGINT UNSIGNED NOT NULL;

-- service
ALTER TABLE service_jobs ADD tenant_id BIGINT UNSIGNED NOT NULL;
ALTER TABLE replacements ADD tenant_id BIGINT UNSIGNED NOT NULL;

-- finance
ALTER TABLE delivery_incentives ADD tenant_id BIGINT UNSIGNED NOT NULL;

-- tally
ALTER TABLE tally_imports ADD tenant_id BIGINT UNSIGNED NOT NULL;
ALTER TABLE tally_exports ADD tenant_id BIGINT UNSIGNED NOT NULL;

-- audit
ALTER TABLE audit_logs ADD tenant_id BIGINT UNSIGNED NOT NULL;

-- communication
ALTER TABLE email_queue ADD tenant_id BIGINT UNSIGNED NOT NULL;

-- analytics
ALTER TABLE driver_eod_audits ADD tenant_id BIGINT UNSIGNED NOT NULL;
```

---

## 4. TENANT-SCOPED UNIQUENESS (STRICT)

### 🔧 APPLY

#### users
```sql
DROP INDEX email;
CREATE UNIQUE INDEX uq_user_email_tenant ON users (tenant_id, email);
```

#### batteries
```sql
DROP INDEX serial_number;
CREATE UNIQUE INDEX uq_battery_serial_tenant ON batteries (tenant_id, serial_number);
```

#### claims
```sql
DROP INDEX claim_number;
CREATE UNIQUE INDEX uq_claim_number_tenant ON claims (tenant_id, claim_number);
```

---

## 5. HANDSHAKE FRAUD PREVENTION (MANDATORY)

### Table: handshake_tasks
```sql
CREATE TABLE handshake_tasks (
    handshake_id BIGINT UNSIGNED NOT NULL,
    task_id BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (handshake_id, task_id),
    UNIQUE KEY uq_task_once (task_id)
);
```

### 🔒 RULE
Incentives MUST be calculated ONLY via handshake_tasks mapping

---

## 6. OUTBOX RELIABILITY FIX (ADD DEDUPE)

### Table: processed_events
```sql
CREATE TABLE processed_events (
    event_uuid CHAR(36) NOT NULL,
    consumer_name VARCHAR(100) NOT NULL,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (event_uuid, consumer_name)
);
```

### 🔒 RULE
- Each consumer checks processed_events before executing
- Guarantees idempotent event handling

---

## 7. IDEMPOTENCY STRICT RULES

### Table exists: api_idempotency_keys

### ADD RULE

If:
- same key + same hash → return cached response
- same key + different hash → **HTTP 409 ERROR**

---

## 8. FILE SECURITY ENFORCEMENT

### 🔒 ADD LOGIC

DO NOT SERVE FILE IF:
```sql
virus_scan_status IN ('PENDING','INFECTED')
OR quarantined_at IS NOT NULL
```

---

## 9. ROLE SYSTEM FINALIZATION

### ❌ REMOVE
- Authorization using users.role

### ✅ FINAL RULE
Use ONLY:

```text
user_roles → roles → role_permissions
```

### Migration Flag
```sql
tenant_settings['rbac_migrated'] = true
```

---

## 10. CLAIM NUMBER SYSTEM FIX

### ❌ REMOVE
- claim_sequences table

### ✅ USE

```sql
tenant_sequences
```

### FORMAT
```
{TENANT}-{YEAR}-{SEQ}
```

Example:
```
ACME-2026-00001
```

---

# 🟡 MEDIUM PRIORITY FIXES

## 11. SOFT DELETE POLICY

### RULE
- Unique values (email, serial) remain RESERVED after delete

---

## 12. USAGE METERING (FOR BILLING)

### Table: tenant_usage_daily
```sql
CREATE TABLE tenant_usage_daily (
    tenant_id BIGINT UNSIGNED,
    date DATE,
    claims_count INT DEFAULT 0,
    active_users INT DEFAULT 0,
    storage_bytes BIGINT DEFAULT 0,
    api_calls INT DEFAULT 0,
    PRIMARY KEY (tenant_id, date)
);
```

---

## 13. OBSERVABILITY BASELINE

### EVERY REQUEST MUST LOG
- request_id
- tenant_id
- user_id

### ADD METRICS
- queue lag
- OTP failures
- refresh failures
- API latency

---

## 14. CLEAN DOCUMENT STRUCTURE

### SPLIT INTO

1. Final SaaS Schema (ONLY FINAL TABLES)
2. Migration Guide (SEPARATE)
3. Roadmap (NO DUPLICATES)

---

# 🟢 FINAL QA STATUS

### AFTER PATCH

- Multi-tenant safe ✅
- Mobile-ready ✅
- Scalable storage-ready ✅
- Secure auth system ✅
- Event-safe architecture ✅
- Fraud-resistant operations ✅

---

# 🚀 FINAL VERDICT

After applying this patch:

👉 System becomes **production-grade SaaS architecture**
👉 Ready for **multi-tenant onboarding at scale**
👉 Ready for **mobile apps + integrations**
👉 Ready for **future microservices extraction**

---

If you want next:

👉 I can convert this into:
- Prisma schema
- Migration SQL scripts
- API contracts (OpenAPI)
- SaaS control panel design

