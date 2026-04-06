CREATE TABLE IF NOT EXISTS crm_customers (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  dealer_id INT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NULL,
  phone VARCHAR(20) NULL,
  city VARCHAR(100) NULL,
  lifecycle_stage ENUM('LEAD','PROSPECT','ACTIVE','REPEAT','CHURNED') NOT NULL DEFAULT 'LEAD',
  source ENUM('HANDSHAKE','MANUAL','IMPORT','API') NOT NULL DEFAULT 'MANUAL',
  total_batteries_bought SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  last_purchase_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_crm_customer_tenant_stage (tenant_id, lifecycle_stage),
  INDEX idx_crm_customer_tenant_dealer (tenant_id, dealer_id),
  CONSTRAINT fk_crm_customer_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_crm_customer_dealer FOREIGN KEY (dealer_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crm_leads (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  customer_id BIGINT UNSIGNED NOT NULL,
  assigned_to INT UNSIGNED NULL,
  title VARCHAR(255) NOT NULL,
  stage ENUM('NEW','CONTACTED','QUALIFIED','PROPOSAL','WON','LOST') NOT NULL DEFAULT 'NEW',
  expected_value DECIMAL(10,2) NULL,
  source VARCHAR(100) NULL,
  follow_up_at TIMESTAMP NULL,
  closed_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_crm_lead_tenant_stage (tenant_id, stage),
  CONSTRAINT fk_crm_lead_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_crm_lead_customer FOREIGN KEY (customer_id) REFERENCES crm_customers(id),
  CONSTRAINT fk_crm_lead_assigned FOREIGN KEY (assigned_to) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crm_lead_activities (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  lead_id BIGINT UNSIGNED NOT NULL,
  user_id INT UNSIGNED NOT NULL,
  activity_type ENUM('NOTE','CALL','EMAIL','WHATSAPP','VISIT','STAGE_CHANGE','FOLLOW_UP') NOT NULL,
  body TEXT NULL,
  old_stage VARCHAR(50) NULL,
  new_stage VARCHAR(50) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_crm_activity_lead (lead_id, created_at),
  CONSTRAINT fk_crm_activity_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_crm_activity_lead FOREIGN KEY (lead_id) REFERENCES crm_leads(id) ON DELETE CASCADE,
  CONSTRAINT fk_crm_activity_user FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crm_segments (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  rules JSON NOT NULL,
  created_by INT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_crm_segment_tenant (tenant_id),
  CONSTRAINT fk_crm_segment_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_crm_segment_creator FOREIGN KEY (created_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crm_campaigns (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  channel ENUM('EMAIL','WHATSAPP','BOTH') NOT NULL,
  segment_id BIGINT UNSIGNED NULL,
  status ENUM('DRAFT','SCHEDULED','DISPATCHING','COMPLETED','CANCELLED') NOT NULL DEFAULT 'DRAFT',
  total_recipients INT UNSIGNED NOT NULL DEFAULT 0,
  sent_count INT UNSIGNED NOT NULL DEFAULT 0,
  failed_count INT UNSIGNED NOT NULL DEFAULT 0,
  created_by INT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_crm_campaign_tenant_status (tenant_id, status),
  CONSTRAINT fk_crm_campaign_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_crm_campaign_segment FOREIGN KEY (segment_id) REFERENCES crm_segments(id),
  CONSTRAINT fk_crm_campaign_creator FOREIGN KEY (created_by) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crm_campaign_recipients (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  campaign_id BIGINT UNSIGNED NOT NULL,
  customer_id BIGINT UNSIGNED NOT NULL,
  channel ENUM('EMAIL','WHATSAPP') NOT NULL,
  address VARCHAR(255) NOT NULL,
  status ENUM('PENDING','SENT','FAILED','OPTED_OUT') NOT NULL DEFAULT 'PENDING',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  sent_at TIMESTAMP NULL,
  UNIQUE KEY uq_crm_campaign_customer_channel (campaign_id, customer_id, channel),
  INDEX idx_crm_campaign_status (campaign_id, status),
  CONSTRAINT fk_crm_recipient_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_crm_recipient_campaign FOREIGN KEY (campaign_id) REFERENCES crm_campaigns(id) ON DELETE CASCADE,
  CONSTRAINT fk_crm_recipient_customer FOREIGN KEY (customer_id) REFERENCES crm_customers(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crm_opt_outs (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  customer_id BIGINT UNSIGNED NOT NULL,
  channel ENUM('EMAIL','WHATSAPP','ALL') NOT NULL,
  opted_out_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reason VARCHAR(255) NULL,
  UNIQUE KEY uq_crm_optout_customer_channel (tenant_id, customer_id, channel),
  CONSTRAINT fk_crm_optout_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_crm_optout_customer FOREIGN KEY (customer_id) REFERENCES crm_customers(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crm_schemes (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  scheme_code VARCHAR(50) NOT NULL,
  type ENUM('DISCOUNT','CASHBACK','VOLUME_INCENTIVE','COMBO_OFFER','LOYALTY') NOT NULL,
  valid_from DATE NOT NULL,
  valid_to DATE NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_crm_scheme_code (tenant_id, scheme_code),
  CONSTRAINT fk_crm_scheme_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crm_scheme_dealer_targets (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  scheme_id BIGINT UNSIGNED NOT NULL,
  dealer_id INT UNSIGNED NOT NULL,
  volume_target INT UNSIGNED NOT NULL DEFAULT 0,
  volume_achieved INT UNSIGNED NOT NULL DEFAULT 0,
  target_hit TINYINT(1) NOT NULL DEFAULT 0,
  target_hit_at TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_crm_scheme_dealer (scheme_id, dealer_id),
  CONSTRAINT fk_crm_target_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_crm_target_scheme FOREIGN KEY (scheme_id) REFERENCES crm_schemes(id) ON DELETE CASCADE,
  CONSTRAINT fk_crm_target_dealer FOREIGN KEY (dealer_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS crm_dealer_sales_daily (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  tenant_id BIGINT UNSIGNED NOT NULL,
  dealer_id INT UNSIGNED NOT NULL,
  sale_date DATE NOT NULL,
  batteries_delivered INT UNSIGNED NOT NULL DEFAULT 0,
  claims_raised INT UNSIGNED NOT NULL DEFAULT 0,
  incentives_paid DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_crm_dealer_sales_day (tenant_id, dealer_id, sale_date),
  CONSTRAINT fk_crm_sales_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id),
  CONSTRAINT fk_crm_sales_dealer FOREIGN KEY (dealer_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
